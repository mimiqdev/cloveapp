import CloveCore
import SwiftUI

struct BatchRenameToast: View {
    let completed: CompletedBatchRename
    let showDetails: () -> Void

    var body: some View {
        Toast(
            message: completed.message, detail: completed.detail,
            actionTitle: completed.hasDetails ? "Details" : nil,
            identifier: "clove.rename.toast", onAction: showDetails)
    }
}

struct BatchRenameDetailsSheet: View {
    let completed: CompletedBatchRename
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(completed.message).font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let failure = completed.result.failure {
                        Text(failure.identity.stem).font(.headline)
                        Text(failure.message).foregroundStyle(Color.clove.reject)
                        ForEach(failure.files, id: \.source) { file in
                            Text(
                                file.url?.lastPathComponent
                                    ?? "Location unknown: \(file.source.lastPathComponent)"
                            )
                            .font(.footnote)
                        }
                    }
                    if !completed.result.temporarySets.isEmpty {
                        Text("Photos left under temporary names").font(.headline)
                        ForEach(completed.result.temporarySets, id: \.identity) { set in
                            Text("\(set.identity.stem) → \(set.stem)")
                            ForEach(set.files, id: \.self) { file in
                                Text(file.lastPathComponent).font(.footnote)
                            }
                        }
                    }
                    if let failure = completed.rescanFailure {
                        Text(failure).foregroundStyle(Color.clove.reject)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Done") { dismiss() }
                .buttonStyle(MoveSheetButtonStyle(secondary: true))
        }
        .padding(20).padding(.top, 12)
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("clove.rename.details")
    }
}
