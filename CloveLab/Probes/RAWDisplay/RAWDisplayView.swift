import LabSupport
import RAWDisplayProbe
import SwiftUI
import UIKit

/// The Lab screen for the RAW display measurements: the full suite and the
/// sustained-load step run from separate buttons so each has its own report.
struct RAWDisplayView: View {
    @Environment(LabSession.self) private var session
    @State private var folder: URL?
    @State private var screenLongEdge = RAWDisplayView.screenLongEdgePixels
    @State private var progress: RAWDisplayProgress?
    @State private var running: Task<Void, Never>?
    @State private var status = "Choose a folder with 12 or more A1 II ARW + HIF pairs."

    var body: some View {
        Form {
            Section("Prepare") {
                Text(
                    "Use local storage with at least 12 RAW + HIF pairs. Keep the charger unplugged and the phone at room temperature for the sustained step."
                )
                Text(
                    "The display suite allows about 4 minutes: RAW variants on the first 12 RAWs, HIF variants on the first 6 pairs, colour, 20-photo swipes, cache and the grid projection. The sustained step allows up to 5 minutes and writes its own report."
                )
                FolderPickerButton { folder = $0 }
                    .disabled(running != nil)
                if let folder { Text(folder.lastPathComponent) }
                Stepper(
                    "Screen long edge: \(screenLongEdge) px",
                    value: $screenLongEdge, in: 400...4_000, step: 100
                )
                .disabled(running != nil)
                Text("Read from this screen's native pixel bounds; adjust only if that is wrong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Measure") {
                Button("Run display suite") { runSuite() }
                    .disabled(folder == nil || running != nil || screenLongEdge <= 0)
                Button("Run sustained load (up to 5 min)") { runSustained() }
                    .disabled(folder == nil || running != nil || screenLongEdge <= 0)
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
                    "Each run writes clove-lab-S8-<timestamp>.json into the tested folder and Files › On My iPhone/iPad › Clove Lab. Export in the footer shares the latest one; attach both the display and sustained JSON to issue #122."
                )
            }
        }
        .navigationTitle("S8 · RAW display")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.rawdisplay")
        .onDisappear { running?.cancel() }
    }

    /// The panel's pixel size in its long direction. The probe stays UIKit-free, so
    /// the screen size is read here and passed into every run.
    private static var screenLongEdgePixels: Int {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let bounds = scenes.first?.screen.nativeBounds ?? .zero
        return Int(max(bounds.width, bounds.height).rounded())
    }

    private func runSuite() {
        guard let folder, screenLongEdge > 0 else { return }
        status = "Measuring…"
        progress = nil
        let options = RAWDisplayOptions(screenLongEdge: screenLongEdge)
        let access = folder.startAccessingSecurityScopedResource()
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await RAWDisplaySuite.run(folder: folder, options: options) { update in
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
                export(report, to: folder)
            } catch is CancellationError {
                status = "Cancelled. The current decoder call drained; no new report exported."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }

    private func runSustained() {
        guard let folder, screenLongEdge > 0 else { return }
        let batteryStart = DeviceBattery.read()
        status = "Measuring sustained load…"
        progress = nil
        let options = sustainedOptions()
        let access = folder.startAccessingSecurityScopedResource()
        running = Task {
            defer {
                if access { folder.stopAccessingSecurityScopedResource() }
                running = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await RAWDisplaySuite.runSustained(
                    folder: folder, options: options,
                    batteryStartPercent: batteryStart.percent
                ) { update in
                    await MainActor.run { progress = update }
                }
            }
            do {
                var report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                let batteryEnd = DeviceBattery.read()
                report.context["batteryStateStart"] = batteryStart.state
                report.context["batteryStateEnd"] = batteryEnd.state
                report.measurements.append(
                    LabMeasurement(
                        name: "battery-end", value: batteryEnd.percent ?? -1, unit: "percent",
                        tags: ["state": batteryEnd.state, "source": "UIDevice batteryLevel"]))
                report.notes.append(
                    "Battery levels are read in the Lab app before and after the loop; -1 means the system reported no level."
                )
                export(report, to: folder)
            } catch is CancellationError {
                status = "Cancelled. The current render drained; no new report exported."
            } catch {
                status = "Run failed: \(error.localizedDescription)"
            }
        }
    }

    /// The sustained step always uses the brief's 300 renders or five minutes.
    private func sustainedOptions() -> RAWDisplayOptions {
        var options = RAWDisplayOptions(screenLongEdge: screenLongEdge)
        options.sustainedMaximumRenders = 300
        options.sustainedMaximumSeconds = 300
        return options
    }

    private func export(_ report: LabReport, to folder: URL) {
        if let url = session.export(report, toTestedFolder: folder) {
            status = "Finished: \(url.lastPathComponent)"
        } else {
            status = "Export needs attention. Check Files › Clove Lab for the Documents copy."
        }
    }
}

/// Battery readings come from UIKit, which is why the probe module never reads them.
private struct DeviceBattery {
    var percent: Double?
    var state: String

    @MainActor
    static func read() -> DeviceBattery {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return DeviceBattery(
            percent: level < 0 ? nil : Double(level) * 100,
            state: name(UIDevice.current.batteryState))
    }

    private static func name(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }
}

#Preview {
    NavigationStack {
        RAWDisplayView().environment(LabSession())
    }
}
