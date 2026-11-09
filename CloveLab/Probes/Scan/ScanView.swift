import ScanProbe
import LabSupport
import SwiftUI

/// Scan — How long does scanning take?
///
/// Picks a card root, writes the generated 2,000-file test tree there, runs the
/// scan suite three times over, and exports one `LabReport`. The heavy work runs
/// off the main thread and holds the picked folder's security scope.
struct ScanView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var tree: ScanTreeSummary?
    @State private var progress: ScanProgress?
    @State private var treeProgress: ScanTreeProgress?
    @State private var running: Task<Void, Never>?
    @State private var status = "Pick the card's root folder, then generate the test tree."

    var body: some View {
        Form {
            Section("Prepare") {
                Text(
                    "Connect the SD card reader and pick the card's root folder, for "
                        + "example EOS_DIGITAL. The test tree is written inside one "
                        + "Clove-Scan folder; nothing else on the card is touched."
                )
                FolderPickerButton { picked in
                    folder = picked
                    tree = nil
                    treeProgress = nil
                    status = "Picked \(picked.lastPathComponent). Generate the test tree."
                }
                .disabled(running != nil)
                if let folder {
                    Text(folder.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Test tree") {
                Text(
                    "2,000 photo files in six DCIM folders, mixed RAW+JPG pairs and "
                        + "standalone files, plus a _Rejected folder and hidden junk. "
                        + "About 2 MB and 1–3 minutes on a card."
                )
                Button("Generate test tree", action: generate)
                    .disabled(folder == nil || running != nil)
                Button("Delete test tree", role: .destructive, action: deleteTree)
                    .disabled(folder == nil || running != nil)
                if let treeProgress {
                    ProgressView(
                        value: Double(treeProgress.completed),
                        total: Double(max(1, treeProgress.total)))
                    Text("\(treeProgress.completed) / \(treeProgress.total) files")
                        .font(.caption)
                }
                if let tree {
                    Text(
                        "\(tree.photoFiles) photo files, \(tree.pairs) RAW+JPG pairs, "
                            + "\(tree.photos) grid items, \(tree.rejectedFiles) in the "
                            + "rejects folder."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Measure") {
                Text(
                    "Three passes over three listing methods and twelve key sets, "
                        + "plus pairing, the rejects folder, and streamed batches. "
                        + "Allow 5–10 minutes on a card. Keep the app open; Cancel "
                        + "stops between steps."
                )
                Button("Run scan suite", action: run)
                    .disabled(folder == nil || running != nil)
                if let progress {
                    ProgressView(
                        value: Double(progress.completed), total: Double(max(1, progress.total)))
                    Text("\(progress.completed) / \(progress.total): \(progress.message)")
                        .font(.caption)
                }
                if running != nil {
                    Button("Cancel", role: .cancel) { running?.cancel() }
                }
                Text(status)
                if let error = session.exportError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("Send results") {
                Text(
                    "The report is saved in the card root and in Files › On My iPhone "
                        + "or iPad › Clove Lab. Attach the S6 JSON to issue #17, or use "
                        + "Export in the footer."
                )
            }
        }
        .navigationTitle("S6 · Scan speed")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.scan")
        .onDisappear { running?.cancel() }
    }

    // MARK: - Actions

    private func generate() {
        guard let folder else { return }
        let access = folder.startAccessingSecurityScopedResource()
        tree = nil
        treeProgress = nil
        status = "Generating the test tree…"
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await ScanTree.makeTree(in: folder, plan: ScanTreePlan()) { update in
                    await MainActor.run { treeProgress = update }
                }
            }
            do {
                let summary = try await worker.value
                tree = summary
                treeProgress = nil
                status = "Test tree ready: \(summary.photoFiles) photo files."
            } catch is CancellationError {
                treeProgress = nil
                status = "Cancelled while generating; a partial tree stays on the card."
            } catch {
                treeProgress = nil
                status = "Tree failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTree() {
        guard let folder else { return }
        let access = folder.startAccessingSecurityScopedResource()
        status = "Deleting the test tree…"
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            do {
                let removed = try await Task.detached(priority: .userInitiated) {
                    try ScanTree.removeTree(in: folder)
                }.value
                tree = nil
                status = removed ? "Test tree deleted." : "There was no test tree to delete."
            } catch {
                status = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func run() {
        guard let folder else { return }
        let target = ScanTree.exists(in: folder) ? ScanTree.treeURL(in: folder) : folder
        let access = folder.startAccessingSecurityScopedResource()
        progress = nil
        status = "Measuring \(target.lastPathComponent)…"
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await ScanBenchmark.run(folder: target) { update in
                    await MainActor.run { progress = update }
                }
            }
            do {
                let report = try await worker.value
                try Task.checkCancellation()
                if let url = session.export(report, toTestedFolder: folder) {
                    status = "Finished: \(url.lastPathComponent). Attach it to issue #17."
                } else {
                    status =
                        "Export needs attention. Check Files › Clove Lab for the Documents copy."
                }
            } catch is CancellationError {
                status = "Cancelled between steps; no report exported."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScanView().environment(LabSession())
    }
}
