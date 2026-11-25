import CloveCore
import SwiftUI

struct BatchRenameNameSheet: View {
    @Bindable var flow: BatchRenameFlow
    let completion: () -> Void
    @Environment(SettingsStore.self) private var store
    @Environment(\.appLanguage) private var language
    @FocusState private var editing: Bool
    @State private var startText: String

    init(flow: BatchRenameFlow, completion: @escaping () -> Void) {
        self.flow = flow
        self.completion = completion
        _startText = State(initialValue: String(flow.options.start))
    }

    static func subtitleText(language: ResolvedAppLanguage = .english) -> String {
        AppLocalization.string("Preview names before applying changes.", language: language)
    }

    static func previewNoteText(language: ResolvedAppLanguage = .english) -> String {
        AppLocalization.string("Replacements are flagged in the preview.", language: language)
    }

    static func confirmTitle(
        totalCount: Int, replacementCount: Int, language: ResolvedAppLanguage = .english
    ) -> String {
        replacementCount > 0
            ? AppLocalization.format(
                "Rename %lld · Replace %lld", language: language,
                Int64(totalCount), Int64(replacementCount))
            : AppLocalization.format(
                "Rename %lld photos", language: language, Int64(totalCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    flow.isRunning
                        ? AppLocalization.format(
                            "Renaming %lld photos…", language: language, Int64(flow.order.count))
                        : AppLocalization.format(
                            "Rename %lld photos", language: language, Int64(flow.order.count))
                )
                .font(.title3.bold())
                Text(Self.subtitleText(language: language))
                    .font(.footnote)
                    .foregroundStyle(Color.clove.text.secondary)
                    .accessibilityIdentifier("clove.rename.subtitle")
                    .reportHeaderControlFrame("clove.rename.subtitle")
            }
            .padding(.top, 8)
            .onTapGesture { editing = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fields
                    destination
                    preview
                }
                .scrollDismissesKeyboard(.interactively)
                .disabled(flow.isRunning)
                .opacity(flow.isRunning ? 0.4 : 1)
            }
            footer
        }
        .padding(20)
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.large])
        .presentationDragIndicator(flow.isRunning ? .hidden : .visible)
        .interactiveDismissDisabled(flow.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.rename.nameSheet")
        .onChange(of: flow.options.start) { _, newValue in
            if Int(startText) != newValue {
                startText = String(newValue)
            }
        }
        .onChange(of: editing) { _, isEditing in
            if !isEditing {
                startText = String(flow.options.start)
            }
        }
        .task(id: flow.options) {
            await flow.prepare(rejectsFolderName: store.settings.rejectsFolderName)
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppLocalization.string("Prefix", language: language))
                TextField(
                    AppLocalization.string("e.g. Wedding_", language: language),
                    text: $flow.options.prefix
                )
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($editing)
                .accessibilityIdentifier("clove.rename.prefix")
            }
            .frame(minHeight: 44)
            .reportHeaderControlFrame("clove.rename.prefix")
            Divider()
            Toggle(
                AppLocalization.string("Add capture date", language: language),
                isOn: $flow.options.addsCaptureDate
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("clove.rename.captureDate")
            .reportHeaderControlFrame("clove.rename.captureDate")
            Divider()
            HStack {
                Text(AppLocalization.string("Separator", language: language))
                Spacer()
                Picker(
                    AppLocalization.string("Separator", language: language),
                    selection: $flow.options.separator
                ) {
                    Text("_").tag(RenameSeparator.underscore)
                    Text("-").tag(RenameSeparator.hyphen)
                    Text(AppLocalization.string("None", language: language))
                        .tag(RenameSeparator.none)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("clove.rename.separator")
            }
            .frame(minHeight: 44)
            .reportHeaderControlFrame("clove.rename.separator")
            Divider()
            HStack(spacing: 8) {
                Text(AppLocalization.string("Start number", language: language))
                Spacer()
                TextField("1", text: $startText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 56, maxWidth: 96)
                    .focused($editing)
                    .onChange(of: startText) { _, newValue in
                        let digitsOnly = newValue.filter { $0.isASCII && $0.isNumber }
                        if digitsOnly != newValue {
                            startText = digitsOnly
                            return
                        }
                        guard !digitsOnly.isEmpty else { return }
                        if let parsed = Int(digitsOnly) {
                            let clamped = min(max(parsed, 0), 999_999_999)
                            if clamped != parsed {
                                startText = String(clamped)
                            }
                            if flow.options.start != clamped {
                                flow.options.start = clamped
                            }
                        } else {
                            let clamped = 999_999_999
                            startText = String(clamped)
                            flow.options.start = clamped
                        }
                    }
                    .accessibilityLabel(AppLocalization.string("Start number", language: language))
                    .accessibilityIdentifier("clove.rename.startInput")
                    .reportHeaderControlFrame("clove.rename.startInput")
                Stepper(
                    AppLocalization.string("Start number", language: language),
                    value: $flow.options.start,
                    in: 0...999_999_999
                )
                .labelsHidden()
                .accessibilityIdentifier("clove.rename.start")
            }
            .frame(minHeight: 44)
            Divider()
            Stepper(value: $flow.options.digits, in: 1...255) {
                HStack {
                    Text(AppLocalization.string("Digits", language: language))
                    Spacer()
                    Text("\(flow.options.digits)")
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("clove.rename.digits")
            .reportHeaderControlFrame("clove.rename.digits")
        }
        .padding(.horizontal, 16)
        .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(AppLocalization.string("Where", language: language))
            VStack(spacing: 0) {
                whereChoice(
                    AppLocalization.string("Keep in place", language: language), moves: false,
                    identifier: "inPlace")
                Divider()
                whereChoice(
                    AppLocalization.string("Move to a new folder", language: language), moves: true,
                    identifier: "newFolder")
                if flow.options.movesToFolder {
                    Divider()
                    TextField(
                        AppLocalization.string("Folder name", language: language),
                        text: $flow.options.folderName
                    )
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing).frame(minHeight: 44)
                    .accessibilityIdentifier("clove.rename.folderName")
                }
            }
            .padding(.horizontal, 16)
            .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func whereChoice(_ label: String, moves: Bool, identifier: String) -> some View {
        Button {
            flow.options.movesToFolder = moves
        } label: {
            HStack {
                Text(label).foregroundStyle(Color.clove.text.primary)
                Spacer()
                if flow.options.movesToFolder == moves { Image(systemName: "checkmark") }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(flow.options.movesToFolder == moves ? [.isSelected] : [])
        .accessibilityIdentifier("clove.rename.where.\(identifier)")
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(AppLocalization.string("Preview · in this order", language: language))
            if let plan = flow.preview {
                VStack(spacing: 0) {
                    ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                        previewRow(row, position: index + 1)
                        if index < plan.rows.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ProgressView(AppLocalization.string("Preparing preview…", language: language))
                    .frame(maxWidth: .infinity).padding()
            }
            Text(Self.previewNoteText(language: language))
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("clove.rename.previewNote")
                .reportHeaderControlFrame("clove.rename.previewNote")
        }
    }

    private func previewRow(_ row: BatchRenameRow, position: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(position)").font(.caption).foregroundStyle(Color.clove.text.secondary)
                .frame(width: 16).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.newStem).font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        row.problems.isEmpty ? Color.clove.text.primary : Color.clove.reject)
                if !row.problems.isEmpty {
                    Text(
                        row.problems.map { $0.explanation(language: language) }.joined(
                            separator: " ")
                    )
                    .font(.caption).foregroundStyle(Color.clove.reject)
                } else if row.replacement != nil {
                    Text(
                        AppLocalization.string(
                            "Replaces a file with this name", language: language)
                    )
                    .font(.caption)
                } else {
                    Text(oldName(row)).font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                Text(
                    row.destinationRelativeFolder.isEmpty
                        ? AppLocalization.string("This folder", language: language)
                        : row.destinationRelativeFolder
                )
                .font(.caption2).foregroundStyle(Color.clove.text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !row.problems.isEmpty || row.replacement != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(
                        row.problems.isEmpty ? Color.clove.label.yellow : Color.clove.reject
                    )
                    .accessibilityLabel(
                        AppLocalization.string(
                            row.problems.isEmpty ? "Replace warning" : "Problem",
                            language: language))
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.rename.preview.\(row.id.stem)")
    }

    private func oldName(_ row: BatchRenameRow) -> String {
        let set = row.item.set.photoSet
        let companions = [set.jpegCompanion, set.heifCompanion].compactMap { $0?.url.pathExtension }
        return ([set.primary.url.lastPathComponent] + companions).joined(separator: " + ")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption).foregroundStyle(Color.clove.text.secondary)
            .padding(.horizontal, 16)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = flow.message {
                Text(AppLocalization.string(message, language: language))
                    .font(.footnote).foregroundStyle(Color.clove.reject)
                    .accessibilityIdentifier("clove.rename.failure")
            }
            let replacements = flow.preview?.replacementCount ?? 0
            let undoWarning = Text(
                replacements > 0
                    ? AppLocalization.format(
                        "Renaming can't be undone. Replaced files move to %@.",
                        language: language, store.settings.rejectsFolderName.rawValue)
                    : AppLocalization.string("Renaming can't be undone.", language: language)
            )
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("clove.rename.warning")
            .reportHeaderControlFrame("clove.rename.warning")

            if flow.isRunning {
                Text(
                    AppLocalization.format(
                        "Renaming %lld of %lld…", language: language,
                        Int64(min(flow.finishedCount + 1, flow.order.count)),
                        Int64(flow.order.count))
                )
                .font(.footnote)
                .accessibilityIdentifier("clove.rename.progress")
                .reportHeaderControlFrame("clove.rename.progress")
                undoWarning
                ProgressView(
                    value: Double(flow.finishedCount), total: Double(max(flow.order.count, 1))
                )
                .tint(Color.clove.accent)
                .accessibilityIdentifier("clove.rename.progressBar")
                .reportHeaderControlFrame("clove.rename.progressBar")
            } else {
                if replacements > 0 {
                    Text(
                        AppLocalization.format(
                            "%lld name is already used in the destination.", language: language,
                            Int64(replacements))
                    )
                    .font(.caption)
                    .accessibilityIdentifier("clove.rename.replacementCount")
                }
                undoWarning
                Button {
                    editing = false
                    Task { await flow.rename(completion: completion) }
                } label: {
                    Text(
                        Self.confirmTitle(
                            totalCount: flow.order.count,
                            replacementCount: replacements,
                            language: language)
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.clove.accent, in: Capsule())
                    .opacity(flow.canRename ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!flow.canRename)
                .accessibilityIdentifier("clove.rename.confirm")
                .reportHeaderControlFrame("clove.rename.confirm")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
