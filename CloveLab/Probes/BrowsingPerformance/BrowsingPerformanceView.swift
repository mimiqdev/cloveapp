import BrowsingPerformanceProbe
import LabSupport
import SwiftUI
import UIKit

/// Current-app browsing measurements over the production packages, with the shared
/// folder picker and report export. No photos, companions or sidecars are modified.
struct BrowsingPerformanceView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var formatFolder: URL?
    @State private var screenLongEdge = BrowsingPerformanceView.screenLongEdgePixels
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
                Stepper(
                    "Screen long edge: \(screenLongEdge) px",
                    value: $screenLongEdge, in: 400...4_000, step: 16
                )
                .disabled(running != nil)
                Picker("Screen edge preset", selection: $screenLongEdge) {
                    Text("Device (\(Self.screenLongEdgePixels) px)")
                        .tag(Self.screenLongEdgePixels)
                    Text(
                        "iPad Pro 13\" (\(BrowsingPerformanceConfiguration.iPadPro13ScreenPixels) px)"
                    )
                    .tag(BrowsingPerformanceConfiguration.iPadPro13ScreenPixels)
                    Text(
                        "iPhone 17 Pro Max (\(BrowsingPerformanceConfiguration.iPhone17ProMaxScreenPixels) px)"
                    )
                    .tag(BrowsingPerformanceConfiguration.iPhone17ProMaxScreenPixels)
                }
                .disabled(running != nil)
                FolderPickerButton(title: "Choose multi-format RAW folder (optional)") {
                    formatFolder = $0
                }
                .disabled(running != nil)
                if let formatFolder {
                    Text("Formats: \(formatFolder.lastPathComponent)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Measure") {
                Text(
                    "Runs scan and metadata, cold and disk-warm thumbnails, detail previews, screen RAW renders, cancelled/full RAW renders, multi-format RAW benchmarks, grouping and features. OS caches cannot be flushed. Grid scrolling is not measured by this Lab flow."
                )
                Button("Run browsing measurements", action: run)
                    .disabled(folder == nil || running != nil || screenLongEdge <= 0)
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

    private static var screenLongEdgePixels: Int {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let bounds = scenes.first?.screen.nativeBounds ?? .zero
        let edge = Int(max(bounds.width, bounds.height).rounded())
        return edge > 0 ? edge : BrowsingPerformanceConfiguration.defaultScreenPixels
    }

    private func run() {
        guard let folder, screenLongEdge > 0 else { return }
        let access = folder.startAccessingSecurityScopedResource()
        let formatAccess = formatFolder?.startAccessingSecurityScopedResource() ?? false
        let configuration = BrowsingPerformanceConfiguration(
            displayPixels: screenLongEdge,
            screenPixels: screenLongEdge,
            detailFormatFolder: formatFolder)
        progress = nil
        status = "Measuring the current production pipelines…"
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                if formatAccess { formatFolder?.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await BrowsingPerformanceProbe.run(
                    folder: folder, configuration: configuration
                ) { update in
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
