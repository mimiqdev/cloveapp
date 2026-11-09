import PreviewProbe
import LabSupport
import SwiftUI

struct PreviewsView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var includeFullRAW = true
    @State private var progress: PreviewProgress?
    @State private var running: Task<Void, Never>?
    @State private var status = "Choose the formats folder or a camera folder."

    var body: some View {
        Form {
            Section("Prepare") {
                Text(
                    "Run formats first, then a folder with at least 200 camera RAW files on your SD card. Repeat on iPhone 17 Pro Max and iPad Pro."
                )
                Text(
                    "Allow 2–10 minutes per run. Detailed decoding samples the first 12 files; grid tests use up to 240. Keep the app open. Cancel waits for the current system decode to finish."
                )
                FolderPickerButton { folder = $0 }
                    .disabled(running != nil)
                if let folder { Text(folder.lastPathComponent) }
                Toggle("Include full-resolution RAW", isOn: $includeFullRAW)
                    .disabled(running != nil)
            }
            Section("Measure") {
                Button("Run preview suite", action: run)
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
                    "The report is saved in the tested folder and in Files › On My iPhone/iPad › Clove Lab. Use Export in the footer and attach the S2 JSON to issue #13. Unsupported methods appear in the report as failures; they do not stop the run."
                )
            }
        }
        .navigationTitle("S2 · Preview speed")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.previews")
        .onDisappear { running?.cancel() }
    }

    private func run() {
        guard let folder else { return }
        let includeFullRAW = includeFullRAW
        status = "Measuring…"
        progress = nil
        // Hold the selected folder's security scope across all asynchronous work.
        let access = folder.startAccessingSecurityScopedResource()
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await PreviewSuite.run(folder: folder, includeFullRAW: includeFullRAW) {
                    update in
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
                    status = "Finished: \(url.lastPathComponent)"
                } else {
                    // Shared exporter may have saved Documents before a card write failed.
                    status =
                        "Export needs attention. Check Files › Clove Lab for the Documents copy."
                }
            } catch is CancellationError {
                status = "Cancelled. Current decode drained; no new report exported."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        PreviewsView().environment(LabSession())
    }
}
