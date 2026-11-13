import BrowsingPerformanceProbe
import LabSupport
import SwiftUI

/// Current-app browsing measurements over the production packages, with the shared
/// folder picker and report export. No photos, companions or sidecars are modified.
struct BrowsingPerformanceView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var progress: BrowsingPerformanceProgress?
    @State private var running: Task<Void, Never>?
    @State private var status = "Choose the generated browsing-2000 folder on local storage."

    var body: some View {
        Form {
            Section("Prepare") {
                Text(
                    "Generate browsing-2000 with mise run fixtures-sets, copy it to a disposable folder on this iPhone, then choose that copy here. Keep Clove Lab open and connected to power. Photos and XMP are unchanged; the JSON report is written beside them."
                )
                FolderPickerButton {
                    folder = $0
                    progress = nil
                    status = "Ready to measure \($0.lastPathComponent)."
                }
                .disabled(running != nil)
                if let folder {
                    Text(folder.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Measure") {
                Text(
                    "Runs scan and metadata, cold and disk-warm thumbnails, detail previews, cancelled/full RAW renders, grouping and features. OS caches cannot be flushed. Grid scrolling is not measured by this Lab flow."
                )
                Button("Run browsing measurements", action: run)
                    .disabled(folder == nil || running != nil)
                if let progress {
                    ProgressView(
                        value: Double(progress.completed), total: Double(max(progress.total, 1)))
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
                    "The Q3 report is saved in the tested folder and Files › On My iPhone › Clove Lab. Use Export in the footer and attach the JSON to issue #219. iPhone target values remain pending until that report is analyzed."
                )
            }
        }
        .navigationTitle("Q3 · Browsing performance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.browsing-performance")
        .onDisappear { running?.cancel() }
    }

    private func run() {
        guard let folder else { return }
        let access = folder.startAccessingSecurityScopedResource()
        progress = nil
        status = "Measuring the current production pipelines…"
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await BrowsingPerformanceProbe.run(folder: folder) { update in
                    await MainActor.run { progress = update }
                }
            }
            do {
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                if let url = session.export(report, toTestedFolder: folder) {
                    status = "Finished: \(url.lastPathComponent). Attach it to issue #219."
                } else {
                    status =
                        "Export needs attention. Check Files › Clove Lab for the Documents copy."
                }
            } catch is CancellationError {
                status = "Cancelled after the current framework call; no report exported."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        BrowsingPerformanceView().environment(LabSession())
    }
}
