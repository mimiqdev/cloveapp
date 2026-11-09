import SpikeS3XMP
import SpikeSupport
import SwiftUI

struct S3View: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var running = false
    @State private var summary = "Choose a disposable test folder on the SD card."
    @State private var report: LabReport?

    var body: some View {
        List {
            Section("XMP and atomic replacement") {
                Text(
                    "Copies ten bundled sidecars into clove-lab-s3, tests two XMP approaches and two replacement methods, then removes that scratch folder."
                )
                Text(
                    "Original photos are never used. An existing clove-lab-s3 folder stops the run."
                )
                FolderPickerButton { folder = $0 }
                    .disabled(running)
                if let folder { Text(folder.lastPathComponent) }
                Button(running ? "Running…" : "Run S3 suite") { run() }
                    .disabled(folder == nil || running)
                    .accessibilityIdentifier("clovelab.s3.run")
                // A simulator-accessible path also verifies the actual suite without
                // relying on an external Files provider or shared simulator device.
                Button("Run in app Documents") {
                    folder = ReportExporter.documentsDirectory
                    run()
                }
                .disabled(running)
                .accessibilityIdentifier("clovelab.s3.documents")
                if running { ProgressView() }
                Text(summary)
                    .accessibilityIdentifier("clovelab.s3.summary")
            }
            if let report {
                Section("Results") {
                    Text("File system: \(report.context["fileSystem"] ?? "unknown")")
                    Text("Scratch folder remains: \(report.context["scratchRemains"] ?? "unknown")")
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in Text(note)
                    }
                    if let name = session.lastReportURL?.lastPathComponent { Text(name) }
                    if let error = session.exportError {
                        Text("Export failed: \(error)").foregroundStyle(.red)
                    }
                    Button("Export to Documents again") { session.export(report) }
                }
            }
            Section("Device check") {
                Text(
                    "Use an exFAT SD card in the reader. Pick an empty test folder and run. Export the S3 JSON using the footer and attach it to issue #14. Repeat on a write-protected card and a nearly full disposable card if available."
                )
                Text(
                    "A failed card export may still leave a Documents copy. Use Export to Documents again if needed."
                )
            }
        }
        .navigationTitle("S3 · XMP")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S3")
    }

    private func run() {
        guard let folder, !running else { return }
        running = true
        summary = "Running copies and replacement checks…"
        Task {
            let result = await Task.detached(priority: .utility) {
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                return XMPSuite.run(in: folder)
            }.value
            report = result
            let successes = result.measurements.filter {
                $0.name == "atomic-confirmed" && $0.value == 1
            }.count
            summary =
                "Finished. \(successes)/12 replacement checks confirmed. Review notes and export the JSON."
            session.export(result, toTestedFolder: folder)
            running = false
        }
    }
}
