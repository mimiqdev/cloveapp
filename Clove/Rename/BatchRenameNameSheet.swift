import CloveCore
import SwiftUI

struct BatchRenameNameSheet: View {
    @Bindable var flow: BatchRenameFlow
    let completion: () -> Void
    @Environment(SettingsStore.self) private var store
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                flow.isRunning
                    ? "Renaming \(flow.order.count) photos…" : "Rename \(flow.order.count) photos"
            )
            .font(.title3.bold()).padding(.top, 8)
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
        .tint(Color.clove.accent)
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.large])
        .presentationDragIndicator(flow.isRunning ? .hidden : .visible)
        .interactiveDismissDisabled(flow.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.rename.nameSheet")
        .task(id: flow.options) {
            await flow.prepare(rejectsFolderName: store.settings.rejectsFolderName)
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prefix")
                TextField("e.g. Wedding_", text: $flow.options.prefix)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing)
                    .accessibilityIdentifier("clove.rename.prefix")
            }
            .frame(minHeight: 44)
            Divider()
            Toggle("Add capture date", isOn: $flow.options.addsCaptureDate)
                .frame(minHeight: 44)
                .accessibilityIdentifier("clove.rename.captureDate")
            Divider()
            Stepper(value: $flow.options.start, in: 0...Int.max) {
                HStack {
                    Text("Start number"); Spacer(); Text("\(flow.options.start)")
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("clove.rename.start")
            Divider()
            Stepper(value: $flow.options.digits, in: 1...255) {
                HStack {
                    Text("Digits"); Spacer(); Text("\(flow.options.digits)")
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("clove.rename.digits")
        }
        .padding(.horizontal, 16)
        .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Where")
            VStack(spacing: 0) {
                whereChoice("Keep in place", moves: false, identifier: "inPlace")
                Divider()
                whereChoice("Move to a new folder", moves: true, identifier: "newFolder")
                if flow.options.movesToFolder {
                    Divider()
                    TextField("Folder name", text: $flow.options.folderName)
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
            sectionTitle("Preview · in this order")
            if let plan = flow.preview {
                VStack(spacing: 0) {
                    ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                        previewRow(row, position: index + 1)
                        if index < plan.rows.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ProgressView("Preparing preview…").frame(maxWidth: .infinity).padding()
            }
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
                    Text(row.problems.map(\.explanation).joined(separator: " "))
                        .font(.caption).foregroundStyle(Color.clove.reject)
                } else if row.replacement != nil {
                    Text("Replaces a file with this name").font(.caption)
                } else {
                    Text(oldName(row)).font(.caption).foregroundStyle(Color.clove.text.secondary)
                }
                Text(
                    row.destinationRelativeFolder.isEmpty
                        ? "This folder" : row.destinationRelativeFolder
                )
                .font(.caption2).foregroundStyle(Color.clove.text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !row.problems.isEmpty || row.replacement != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(
                        row.problems.isEmpty ? Color.clove.label.yellow : Color.clove.reject
                    )
                    .accessibilityLabel(row.problems.isEmpty ? "Replace warning" : "Problem")
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
                Text(message).font(.footnote).foregroundStyle(Color.clove.reject)
                    .accessibilityIdentifier("clove.rename.failure")
            }
            let replacements = flow.preview?.replacementCount ?? 0
            if replacements > 0 {
                Text(
                    "\(replacements) \(replacements == 1 ? "name is" : "names are") already used in the destination."
                )
                .font(.caption)
                .accessibilityIdentifier("clove.rename.replacementCount")
            }
            Text(
                "Renaming can't be undone."
                    + (replacements > 0
                        ? " Replaced files move to \(store.settings.rejectsFolderName.rawValue)."
                        : "")
            )
            .font(.caption).foregroundStyle(Color.clove.text.secondary)
            .multilineTextAlignment(.center)
            if flow.isRunning {
                ProgressView(
                    value: Double(flow.finishedCount), total: Double(max(flow.order.count, 1)))
                Text(
                    "Renaming \(min(flow.finishedCount + 1, flow.order.count)) of \(flow.order.count)…"
                )
                .font(.footnote).accessibilityIdentifier("clove.rename.progress")
            } else {
                Button(role: replacements > 0 ? .destructive : nil) {
                    editing = false
                    Task { await flow.rename(completion: completion) }
                } label: {
                    Text(
                        replacements > 0
                            ? "Rename \(flow.order.count) · Replace \(replacements)"
                            : "Rename \(flow.order.count) photos"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(
                        replacements > 0 ? Color.clove.reject : Color.clove.accent, in: Capsule()
                    )
                    .opacity(flow.canRename ? 1 : 0.4)
                }
                .buttonStyle(.plain).disabled(!flow.canRename)
                .accessibilityIdentifier("clove.rename.confirm")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
