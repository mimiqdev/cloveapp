import CloveCore
import SwiftUI

/// Move results use the same glass toast as marking failures, with a single contextual action.
struct MoveRejectsToast: View {
    let browsing: BrowsingModel
    let completed: CompletedRejectMove
    let showDetails: () -> Void

    var body: some View {
        let copy = RejectMoveToast(
            result: completed.result, rejectsFolderName: completed.rejectsFolderName)
        Toast(
            message: copy.message,
            detail: [copy.failureMessage, copy.skippedMessage, copy.noLongerRejectedMessage]
                .compactMap { $0 }.joined(separator: " ").nilIfEmpty,
            actionTitle: copy.showsDetails ? "Details" : "Undo",
            identifier: "clove.moves.toast",
            onAction: {
                if copy.showsDetails { showDetails() } else { browsing.undoRejectMove(completed) }
            })
    }
}

/// Per-photo failures remain visible in place, and Try again submits only failed sets.
struct MoveRejectsDetailsSheet: View {
    let browsing: BrowsingModel
    @Environment(\.dismiss) private var dismiss
    @State private var current: CompletedRejectMove
    @State private var retryError: String?
    @State private var isRetrying = false

    init(browsing: BrowsingModel, completed: CompletedRejectMove) {
        self.browsing = browsing
        _current = State(initialValue: completed)
    }

    var body: some View {
        let details = RejectMoveDetails(result: current.result)
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
                if let notRejected = details.noLongerRejectedMessage {
                    Text(notRejected).font(.footnote)
                }
                if let retryError {
                    Text(retryError).foregroundStyle(Color.clove.reject)
                        .accessibilityIdentifier("clove.moves.details.error")
                }
            }
            HStack(spacing: 10) {
                Button("Done") {
                    browsing.dismissRejectMoveToast()
                    dismiss()
                }
                .buttonStyle(MoveSheetButtonStyle(secondary: true))
                .disabled(isRetrying)
                .accessibilityIdentifier("clove.moves.details.done")
                if details.canRetry {
                    Button("Try again") { retry() }
                        .buttonStyle(MoveSheetButtonStyle())
                        .disabled(isRetrying)
                        .accessibilityIdentifier("clove.moves.details.retry")
                }
            }
            if isRetrying { ProgressView().accessibilityIdentifier("clove.moves.details.retrying") }
        }
        .padding(20).padding(.top, 12)
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isRetrying)
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

    private func retry() {
        guard !isRetrying else { return }
        isRetrying = true
        retryError = nil
        browsing.retryRejectMove(current) { outcome in
            isRetrying = false
            switch outcome {
            case .success(let retried):
                current = CompletedRejectMove(
                    result: retried, keptIdentities: current.keptIdentities,
                    rejectsFolderName: current.rejectsFolderName,
                    folder: current.folder, openGeneration: current.openGeneration)
                if RejectMoveDetails(result: retried).rows.isEmpty { dismiss() }
            case .failure(let refusal as RejectMoveRefusal):
                if case .undone = refusal {
                    retryError = "This move was undone."
                } else {
                    retryError = "The failed photos couldn't be retried."
                }
            case .failure:
                retryError = "The failed photos couldn't be retried."
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
