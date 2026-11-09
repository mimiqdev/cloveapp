import EmbeddedMetadataProbe
import LabSupport
import SwiftUI

/// Embedded metadata confirmation uses the same verification code as the macOS fixture tests.
struct EmbeddedMetadataView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var isRunning = false
    @State private var results: [EmbeddedWriteResult] = []
    @State private var message = "Choose a folder with copies of the four S4 fixtures."

    var body: some View {
        List {
            Section("Prepare") {
                Text(
                    "Use a flat folder with JPEG, HEIC/HEIF (including camera .HIF), Pentax DNG and iPhone ProRAW DNG copies. Allow about 1 minute."
                )
                Text(
                    "The check works on temporary copies. Your selected images stay unchanged. The JSON report is added to the folder and Clove Lab Documents."
                )
                FolderPickerButton { folder = $0 }
                    .disabled(isRunning)
                if let folder { Text(folder.lastPathComponent).font(.caption) }
                Button("Run metadata check") { run() }
                    .disabled(folder == nil || isRunning)
                    .accessibilityIdentifier("clovelab.embedded-metadata.run")
            }
            Section("Result") {
                if isRunning { ProgressView("Comparing image bytes, pixels and metadata…") }
                Text(message)
                    .accessibilityIdentifier("clovelab.embedded-metadata.status")
                Text(
                    "DNG writes are expected to be unavailable. The re-encoding comparison is expected to change pixels. JPEG's native copy can drop MakerNotes and rewrite EXIF/GPS; the packet comparison checks preservation separately."
                )
                .font(.caption)
            }
            Section("Seeded control") {
                Text(
                    "A seeded result compares against the seeded file and does not show preservation against the camera original. JPEG now uses packet splice for seeding to keep original bytes outside XMP. HEIF uses a native seed, which may already discard or normalize camera metadata. Check camera-original rows too."
                )
                .font(.caption)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Section(result.file) {
                    Text("\(result.control) · \(result.method.rawValue)").font(.caption)
                    if let seedDescription = result.seedDescription {
                        Text(seedDescription).font(.caption)
                    }
                    if let error = result.error {
                        Text(error)
                    } else {
                        LabeledContent(
                            "Marks read back", value: result.marksReadBack ? "Yes" : "No")
                        LabeledContent(
                            "Image bytes unchanged", value: result.payloadUnchanged ? "Yes" : "No")
                        if result.payloadRenumberedOnly {
                            Text("HEIF item IDs renumbered only; image content unchanged.")
                                .font(.caption)
                        }
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
        .navigationTitle("S4 · Embedded metadata")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.embedded-metadata")
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
    NavigationStack { EmbeddedMetadataView().environment(LabSession()) }
}
