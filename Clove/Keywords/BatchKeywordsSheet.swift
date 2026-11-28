import CloveCore
import SwiftUI

/// Focused batch keyword editor over the active visible grid selection (`browsing.batchTargets`).
struct BatchKeywordsSheet: View {
    let browsing: BrowsingModel
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    @State private var hasAppliedInSheet = false
    @State private var stagedKeywords: [String] = []

    static func navigationTitle(isStagedConfirmation: Bool, language: ResolvedAppLanguage) -> String
    {
        AppLocalization.string(
            isStagedConfirmation ? "Add Keywords" : "Keywords", language: language)
    }

    static func confirmTitle(targetCount: Int, language: ResolvedAppLanguage) -> String {
        AppLocalization.format("Add to %lld Photos", language: language, Int64(targetCount))
    }

    static func stagedAfterAdding(_ tokens: [String], to staged: [String]) -> [String] {
        PhotoKeywords.deduplicated(staged + tokens)
    }

    static func combinedStagedKeywords(_ staged: [String], entered: [String]) -> [String] {
        PhotoKeywords.deduplicated(staged + entered)
    }

    private var isStagedConfirmation: Bool { store.settings.confirmBatchActions }
    private var targets: [GridPhoto] { browsing.batchTargets }
    private var canOperate: Bool { !targets.isEmpty && browsing.canMark }
    private var enteredKeywords: [String] { BatchKeywords.parse(inputText) }
    private var canSubmitEntered: Bool { canOperate && !enteredKeywords.isEmpty }
    private var canConfirmStaged: Bool { canOperate && !stagedKeywords.isEmpty }
    private var commonKeywords: [String] { BatchKeywords.commonKeywords(in: targets) }
    private var mixedKeywords: [String] { BatchKeywords.mixedKeywords(in: targets) }
    private var suggestions: [String] {
        BatchKeywords.suggestions(
            in: browsing.allPlacedPhotos,
            targets: targets,
            excluding: isStagedConfirmation ? stagedKeywords : enteredKeywords)
    }

    var body: some View {
        NavigationStack {
            List {
                inputSection
                if isStagedConfirmation {
                    if !suggestions.isEmpty {
                        suggestionsSection(
                            title: AppLocalization.string("Recent", language: language))
                    }
                } else {
                    if !commonKeywords.isEmpty || !mixedKeywords.isEmpty {
                        commonSection
                    }
                    if !suggestions.isEmpty {
                        suggestionsSection(
                            title: AppLocalization.string("Suggestions", language: language))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isStagedConfirmation {
                    stagedConfirmFooter
                }
            }
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(
                Self.navigationTitle(isStagedConfirmation: isStagedConfirmation, language: language)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isStagedConfirmation || !hasAppliedInSheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLocalization.string("Cancel", language: language)) {
                            dismiss()
                        }
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityIdentifier("clove.keywords.cancel")
                    }
                }
                if !isStagedConfirmation && hasAppliedInSheet {
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
        .tint(theme.tokens.accent.color)
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
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.keywords.summary")
    }

    private var inputSection: some View {
        Section {
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
                .accessibilityIdentifier("clove.keywords.input")

                Button {
                    submitEnteredKeywords()
                } label: {
                    Text(AppLocalization.string("Add", language: language))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.tokens.accent.color)
                .disabled(!canSubmitEntered)
                .accessibilityIdentifier("clove.keywords.apply")
            }
        } header: {
            selectionSummary
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    AppLocalization.string(
                        "Separate multiple keywords with commas.", language: language)
                )
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)

                if isStagedConfirmation && !stagedKeywords.isEmpty {
                    chipFlow {
                        ForEach(stagedKeywords, id: \.self) { keyword in
                            removableChip(
                                keyword,
                                identifier: "clove.keywords.staged.\(keyword)"
                            ) {
                                unstageKeyword(keyword)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
        .listRowBackground(theme.tokens.card.color)
    }

    @ViewBuilder
    private var commonSection: some View {
        if !commonKeywords.isEmpty || !mixedKeywords.isEmpty {
            chipRow {
                if !commonKeywords.isEmpty {
                    sectionHeader(
                        AppLocalization.string("On all selected", language: language))
                    chipFlow {
                        ForEach(commonKeywords, id: \.self) { keyword in
                            removableChip(
                                keyword,
                                identifier: "clove.keywords.remove.\(keyword)"
                            ) {
                                removeCommonKeyword(keyword)
                            }
                        }
                    }
                }
                if !mixedKeywords.isEmpty {
                    mixedKeywordsText
                        .padding(.top, commonKeywords.isEmpty ? 0 : 4)
                }
            }
        }
    }

    private var mixedKeywordsText: some View {
        Text(
            AppLocalization.format(
                "Also on some selected: %@", language: language,
                mixedKeywords.joined(separator: ", "))
        )
        .font(.caption)
        .foregroundStyle(Color.clove.text.secondary)
        .accessibilityIdentifier("clove.keywords.mixed")
    }

    private func suggestionsSection(title: String) -> some View {
        chipRow {
            sectionHeader(title)
            chipFlow {
                ForEach(suggestions, id: \.self) { keyword in
                    keywordChip(
                        accessibilityLabel: AppLocalization.format(
                            "Add %@", language: language, keyword),
                        identifier: "clove.keywords.suggestion.\(keyword)"
                    ) {
                        if isStagedConfirmation {
                            stageKeywords([keyword])
                        } else {
                            applySuggestion(keyword)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .imageScale(.small)
                                .foregroundStyle(Color.clove.accent)
                            Text(keyword)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func chipFlow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        KeywordChipLayout(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removableChip(
        _ keyword: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        keywordChip(
            accessibilityLabel: AppLocalization.format("Remove %@", language: language, keyword),
            identifier: identifier,
            action: action
        ) {
            HStack(spacing: 6) {
                Text(keyword)
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(Color.clove.text.secondary)
            }
        }
    }

    private func keywordChip<Label: View>(
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 36)
                .foregroundStyle(Color.clove.text.primary)
                .background(Color.clove.surface.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.clove.separator, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(!canOperate)
        .opacity(canOperate ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.clove.text.secondary)
    }

    private var stagedConfirmFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.clove.separator)
            Button {
                confirmStagedKeywords()
            } label: {
                Text(Self.confirmTitle(targetCount: targets.count, language: language))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(theme.tokens.accent.color)
            .disabled(!canConfirmStaged)
            .accessibilityIdentifier("clove.keywords.confirm")
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.clove.surface.sheet)
    }

    private func submitEnteredKeywords() {
        let tokens = enteredKeywords
        guard canOperate, !tokens.isEmpty else { return }
        if isStagedConfirmation {
            stageKeywords(tokens)
            inputText = ""
            return
        }
        isInputFocused = false
        browsing.applyBatch(.addKeywords(tokens), settings: store.settings)
        dismiss()
    }

    private func stageKeywords(_ tokens: [String]) {
        guard canOperate else { return }
        stagedKeywords = Self.stagedAfterAdding(tokens, to: stagedKeywords)
    }

    private func unstageKeyword(_ keyword: String) {
        stagedKeywords.removeAll { $0 == keyword }
    }

    private func confirmStagedKeywords() {
        let combined = Self.combinedStagedKeywords(stagedKeywords, entered: enteredKeywords)
        guard canOperate, !stagedKeywords.isEmpty, !combined.isEmpty else { return }
        isInputFocused = false
        browsing.applyBatch(.addKeywords(combined), settings: store.settings)
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
