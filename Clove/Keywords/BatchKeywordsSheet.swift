import CloveCore
import SwiftUI

/// Focused batch keyword editor over the active visible grid selection (`browsing.batchTargets`).
struct BatchKeywordsSheet: View {
    let browsing: BrowsingModel
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    @State private var hasAppliedInSheet = false

    private var targets: [GridPhoto] { browsing.batchTargets }
    private var canOperate: Bool { !targets.isEmpty && browsing.canMark }
    private var enteredKeywords: [String] { BatchKeywords.parse(inputText) }
    private var canSubmitEntered: Bool { canOperate && !enteredKeywords.isEmpty }
    private var commonKeywords: [String] { BatchKeywords.commonKeywords(in: targets) }
    private var mixedKeywords: [String] { BatchKeywords.mixedKeywords(in: targets) }
    private var suggestions: [String] {
        BatchKeywords.suggestions(
            in: browsing.allPlacedPhotos, targets: targets, excluding: enteredKeywords)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectionSummary
                    inputSection
                    if !commonKeywords.isEmpty || !mixedKeywords.isEmpty {
                        commonSection
                    }
                    if !suggestions.isEmpty {
                        suggestionsSection
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(AppLocalization.string("Keywords", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !hasAppliedInSheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLocalization.string("Cancel", language: language)) {
                            dismiss()
                        }
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityIdentifier("clove.keywords.cancel")
                    }
                }
                if hasAppliedInSheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Done", language: language)) {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityIdentifier("clove.keywords.done")
                    }
                }
            }
        }
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.keywords.sheet")
    }

    private var selectionSummary: some View {
        HStack(spacing: 6) {
            Text(
                AppLocalization.format(
                    "%lld selected", language: language, Int64(targets.count))
            )
            .foregroundStyle(Color.clove.text.primary)
            if browsing.hiddenSelectedCount > 0 {
                Text("·")
                    .foregroundStyle(Color.clove.text.secondary)
                Text(
                    AppLocalization.format(
                        "%lld hidden by filter", language: language,
                        Int64(browsing.hiddenSelectedCount))
                )
                .foregroundStyle(Color.clove.text.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.keywords.summary")
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(
                    AppLocalization.string(
                        "Add keywords, separated by commas", language: language),
                    text: $inputText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit { submitEnteredKeywords() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("clove.keywords.input")

                Button {
                    submitEnteredKeywords()
                } label: {
                    Text(AppLocalization.string("Add", language: language))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .foregroundStyle(.white)
                        .background(Color.clove.accent, in: Capsule())
                        .opacity(canSubmitEntered ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitEntered)
                .accessibilityIdentifier("clove.keywords.apply")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))

            Text(
                AppLocalization.string(
                    "Separate multiple keywords with commas.", language: language)
            )
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var commonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !commonKeywords.isEmpty {
                sectionTitle(AppLocalization.string("On all selected", language: language))
                KeywordChipLayout(spacing: 8) {
                    ForEach(commonKeywords, id: \.self) { keyword in
                        Button {
                            removeCommonKeyword(keyword)
                        } label: {
                            HStack(spacing: 6) {
                                Text(keyword)
                                    .lineLimit(1)
                                Image(systemName: "xmark.circle.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(Color.clove.text.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minHeight: 36)
                            .foregroundStyle(Color.clove.text.primary)
                            .background(Color.clove.surface.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.clove.separator, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canOperate)
                        .opacity(canOperate ? 1 : 0.4)
                        .accessibilityLabel(
                            AppLocalization.format("Remove %@", language: language, keyword)
                        )
                        .accessibilityHint(
                            AppLocalization.string(
                                "Removes this keyword from all selected photos.",
                                language: language)
                        )
                        .accessibilityIdentifier("clove.keywords.remove.\(keyword)")
                    }
                }
            }
            if !mixedKeywords.isEmpty {
                Text(
                    AppLocalization.format(
                        "Also on some selected: %@", language: language,
                        mixedKeywords.joined(separator: ", "))
                )
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("clove.keywords.mixed")
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(AppLocalization.string("Suggestions", language: language))
            KeywordChipLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { keyword in
                    Button {
                        applySuggestion(keyword)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .imageScale(.small)
                                .foregroundStyle(Color.clove.accent)
                            Text(keyword)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 36)
                        .foregroundStyle(Color.clove.text.primary)
                        .background(Color.clove.surface.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.clove.separator, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOperate)
                    .opacity(canOperate ? 1 : 0.4)
                    .accessibilityLabel(
                        AppLocalization.format("Add %@", language: language, keyword)
                    )
                    .accessibilityHint(
                        AppLocalization.string(
                            "Adds this keyword to all selected photos.", language: language)
                    )
                    .accessibilityIdentifier("clove.keywords.suggestion.\(keyword)")
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.clove.text.secondary)
            .padding(.horizontal, 4)
    }

    private func submitEnteredKeywords() {
        let tokens = enteredKeywords
        guard canOperate, !tokens.isEmpty else { return }
        isInputFocused = false
        browsing.applyBatch(.addKeywords(tokens), settings: store.settings)
        dismiss()
    }

    private func applySuggestion(_ keyword: String) {
        guard canOperate else { return }
        browsing.applyBatch(.addKeywords([keyword]), settings: store.settings)
        hasAppliedInSheet = true
    }

    private func removeCommonKeyword(_ keyword: String) {
        guard canOperate else { return }
        browsing.applyBatch(.removeKeywords([keyword]), settings: store.settings)
        hasAppliedInSheet = true
    }
}

private struct KeywordChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: proposal.width, height: nil))
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = lineWidth > 0 ? lineWidth + spacing + size.width : size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        maxLineWidth = max(maxLineWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(
            width: proposal.width ?? maxLineWidth,
            height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
