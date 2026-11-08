import SpikeS5Grouping
import SpikeSupport
import SwiftUI

struct S5View: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var result: GroupingRun?
    @State private var running: Task<Void, Never>?
    @State private var completed = 0
    @State private var total = 1
    @State private var status =
        "Choose a folder with at least 300 photos and several bursts, ideally from two bodies."

    var body: some View {
        Form {
            Section("Prepare") {
                Text(
                    "Connect the SD reader or external SSD. Choose a shooting folder, including its subfolders. RAW+JPEG pairs use the RAW file. Up to 600 photos are measured."
                )
                Text(
                    "Allow about 2–10 minutes for measurement, then 5–15 minutes to review burst boundaries. Keep the app open. Photos and XMP are unchanged."
                )
                FolderPickerButton {
                    folder = $0
                    result = nil
                }
                .disabled(running != nil)
                if let folder { Text(folder.lastPathComponent) }
                Button("Compute metadata and groups", action: run)
                    .disabled(folder == nil || running != nil)
                if running != nil {
                    ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    Text("\(completed) / \(total) photos")
                    Button("Cancel", role: .cancel) { running?.cancel() }
                }
                Text(status)
            }
            if let result {
                Section("Proposed groups") {
                    Text(
                        "\(result.photos.count) photos · \(result.groups.count) groups · \(result.photos.filter { $0.captureTime == nil }.count) without capture time"
                    )
                    Text(
                        "Trial: 2 s time gap, Vision revision 2 distance ≤ 0.5 at 400 pixels. Missing features split. Missing serial uses model only and may mix bodies."
                    )
                    ForEach(Array(result.groups.enumerated()), id: \.offset) { index, group in
                        DisclosureGroup("Group \(index + 1) · \(group.count) photos") {
                            ForEach(group, id: \.self) { Text($0).font(.caption) }
                        }
                    }
                }
                Section("Label boundaries") {
                    Text(
                        "Review adjacent photos within each body. Start new group means different burst or composition. Confirm a correct suggestion, or change the toggle to fix a wrong split or merge. Only reviewed boundaries count as labels; you can save a partial review."
                    )
                    Text(
                        "\(result.boundaries.filter { $0.expectedSplit != nil }.count) / \(result.boundaries.count) reviewed"
                    )
                    ForEach(result.boundaries.indices, id: \.self) { index in
                        boundaryRow(index)
                    }
                }
                Section("Save and send") {
                    Button("Save report with labels", action: export)
                    Text(
                        "Use Export in the footer and attach the S5 JSON to issue #16. Copies appear in the tested folder and Files › On My iPhone/iPad › Clove Lab. Reports include file names and camera identifiers."
                    )
                    if let error = session.exportError { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("S5 · Grouping data")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S5")
        .onDisappear { running?.cancel() }
    }

    @ViewBuilder private func boundaryRow(_ index: Int) -> some View {
        if let result {
            let boundary = result.boundaries[index]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    photo(boundary.left, in: result)
                    photo(boundary.right, in: result)
                }
                Text(
                    "Gap \(boundary.gap, specifier: "%.3f") s · distance \(boundary.distance.map { String(format: "%.3f", $0) } ?? "unavailable")"
                )
                .font(.caption)
                Toggle(
                    "Start new group",
                    isOn: Binding(
                        get: {
                            self.result?.boundaries[index].expectedSplit ?? boundary.proposedSplit
                        },
                        set: { self.result?.boundaries[index].expectedSplit = $0 }))
                if boundary.expectedSplit == nil {
                    Button("Confirm suggestion: \(boundary.proposedSplit ? "split" : "same group")")
                    {
                        self.result?.boundaries[index].expectedSplit = boundary.proposedSplit
                    }
                } else {
                    Text("Reviewed").foregroundStyle(.secondary)
                    Button("Clear label") { self.result?.boundaries[index].expectedSplit = nil }
                }
            }
        }
    }

    private func photo(_ id: String, in result: GroupingRun) -> some View {
        VStack {
            if let data = result.thumbnails[id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 110)
            } else {
                Label("No embedded preview", systemImage: "photo.badge.exclamationmark")
            }
            Text(id).font(.caption2).lineLimit(3)
        }
        .frame(maxWidth: .infinity)
    }

    private func run() {
        guard let folder else { return }
        result = nil
        completed = 0
        total = 1
        status = "Measuring…"
        let access = folder.startAccessingSecurityScopedResource()
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .utility) {
                try await GroupingSuite.run(folder: folder) { done, count in
                    await MainActor.run {
                        completed = done; total = count
                    }
                }
            }
            do {
                result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                status = "Measurement complete. Review boundaries, then save the report."
            } catch is CancellationError {
                result = nil
                status = "Cancelled after the current image. No report saved."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }

    private func export() {
        guard var report = result?.labeledReport(), let folder else { return }
        report.createdAt = Date()
        if let url = session.export(report, toTestedFolder: folder) {
            status = "Saved: \(url.lastPathComponent)"
        } else {
            status = "Export needs attention. Check Files › Clove Lab for the Documents copy."
        }
    }
}

#Preview {
    NavigationStack { S5View().environment(LabSession()) }
}
