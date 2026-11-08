import SpikeS4Metadata
import SpikeSupport
import SwiftUI

/// S4 confirmation uses the same verification code as the macOS fixture tests.
struct S4View: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var isRunning = false
    @State private var results: [EmbeddedWriteResult] = []
    @State private var message = "Choose a folder with copies of the four S4 fixtures."

    var body: some View {
        List {
            Section("Prepare") {
                Text(
                    "Use a flat folder with the camera JPEG, generated HEIC, Pentax DNG and iPhone ProRAW DNG. Allow about 1 minute."
                )
                Text(
                    "The check works on temporary copies. Your selected images stay unchanged. The JSON report is added to the folder and Clove Lab Documents."
                )
                FolderPickerButton { folder = $0 }
                    .disabled(isRunning)
                if let folder { Text(folder.lastPathComponent).font(.caption) }
                Button("Run metadata check") { run() }
                    .disabled(folder == nil || isRunning)
                    .accessibilityIdentifier("clovelab.S4.run")
            }
            Section("Result") {
                if isRunning { ProgressView("Comparing image bytes, pixels and metadata…") }
                Text(message)
                    .accessibilityIdentifier("clovelab.S4.status")
                Text(
                    "DNG writes are expected to be unavailable. The re-encoding comparison is expected to change pixels. JPEG's native copy can alter GPS precision; the packet comparison checks preservation separately."
                )
                .font(.caption)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Section(result.file) {
                    Text("\(result.control) · \(result.method.rawValue)").font(.caption)
                    if let error = result.error {
                        Text(error)
                    } else {
                        LabeledContent(
                            "Marks read back", value: result.marksReadBack ? "Yes" : "No")
                        LabeledContent(
                            "Image bytes unchanged", value: result.payloadUnchanged ? "Yes" : "No")
                        LabeledContent(
                            "Pixels unchanged", value: result.pixelsUnchanged ? "Yes" : "No")
                        LabeledContent(
                            "Existing metadata changes",
                            value: String(result.changedExistingMetadata.count))
                    }
                }
            }
            if let url = session.lastReportURL, !results.isEmpty {
                Section("Export") {
                    Text(url.lastPathComponent).font(.caption)
                    ShareLink("Export S4 JSON", item: url)
                    Text(
                        "Attach this JSON to issue #15. A copy is also in Files → On My iPhone → Clove Lab."
                    )
                }
            }
            if let error = session.exportError { Text("Report export failed: \(error)") }
        }
        .navigationTitle("S4 Metadata")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S4")
    }

    private func run() {
        guard let folder, !isRunning else { return }
        isRunning = true
        results = []
        message = "Running…"
        Task {
            do {
                let (report, rows) = try await Task.detached(priority: .userInitiated) {
                    try SecurityScopedAccess.withAccess(to: folder) { folder in
                        try MetadataExperiment.run(folder: folder)
                    }
                }.value
                results = rows
                if session.export(report, toTestedFolder: folder) != nil {
                    message =
                        "Finished \(rows.count) checks. Export the S4 JSON below, including any unavailable writes."
                } else {
                    message = "Checks finished. Report export failed; see the error below."
                }
            } catch {
                message = "Check failed: \(error)"
            }
            isRunning = false
        }
    }
}

#Preview {
    NavigationStack { S4View().environment(LabSession()) }
}
