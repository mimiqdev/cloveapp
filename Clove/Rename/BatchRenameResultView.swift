import CloveCore
import SwiftUI

struct BatchRenameToast: View {
    let completed: CompletedBatchRename
    let showDetails: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        Toast(
            message: completed.localizedMessage(language: language),
            detail: completed.localizedDetail(language: language),
            actionTitle: completed.hasDetails
                ? AppLocalization.string("Details", language: language) : nil,
            identifier: "clove.rename.toast", onAction: showDetails)
    }
}

struct BatchRenameDetailsSheet: View {
    let completed: CompletedBatchRename
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(completed.localizedMessage(language: language)).font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let failure = completed.result.failure {
                        Text(failure.identity.stem).font(.headline)
                        Text(failure.message).foregroundStyle(Color.clove.reject)
                        ForEach(failure.files, id: \.source) { file in
                            Text(
                                file.url?.lastPathComponent
                                    ?? AppLocalization.format(
                                        "Location unknown: %@", language: language,
                                        file.source.lastPathComponent)
                            )
                            .font(.footnote)
                        }
                    }
                    if !completed.result.temporarySets.isEmpty {
                        Text(
                            AppLocalization.string(
                                "Photos left under temporary names", language: language)
                        )
                        .font(.headline)
                        ForEach(completed.result.temporarySets, id: \.identity) { set in
                            Text("\(set.identity.stem) → \(set.stem)")
                            ForEach(set.files, id: \.self) { file in
                                Text(file.lastPathComponent).font(.footnote)
                            }
                        }
                    }
                    if let failure = completed.rescanFailure {
                        Text(AppLocalization.string(failure, language: language))
                            .foregroundStyle(Color.clove.reject)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(AppLocalization.string("Done", language: language)) { dismiss() }
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
