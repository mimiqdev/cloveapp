import FolderAccessProbe
import LabSupport
import SwiftUI

@MainActor
@Observable
private final class FolderAccessModel {
    var snapshot: AccessSnapshot?
    var busy = false
    var media: AccessMedia = .local
    var scenario = "baseline"
    private var watch: Task<Void, Never>?
    let experiment: AccessExperiment

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0]
        experiment = AccessExperiment(
            storeURL: base.appendingPathComponent("CloveLab/FolderAccess/recents-v1.json"))
    }

    func load() async { snapshot = await experiment.load() }

    func perform(_ operation: @escaping @Sendable (AccessExperiment) async -> AccessSnapshot) {
        guard !busy else { return }
        busy = true
        Task {
            snapshot = await operation(experiment)
            busy = false
        }
    }

    func startWatch() {
        guard watch == nil else { return }
        watch = Task {
            snapshot = await experiment.startWatch()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                guard !Task.isCancelled else { break }
                snapshot = await experiment.poll()
            }
            await experiment.stopWatch()
            snapshot = await experiment.snapshot()
            watch = nil
        }
    }

    func stopWatch() { watch?.cancel() }
}

/// Lab-only Recents and measurements. All filesystem work is in the reusable folder-access actor.
struct FolderAccessView: View {
    @Environment(LabSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = FolderAccessModel()
    @State private var exportName: String?
    @State private var confirmFill = false
    @State private var confirmCleanup = false

    var body: some View {
        Form {
            Section("Folder and Lab-only Recents") {
                Picker("Media (recorded in report)", selection: $model.media) {
                    ForEach(AccessMedia.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                FolderPickerButton { url in
                    let media = model.media
                    model.perform { await $0.pick(url, media: media) }
                }
                .disabled(model.busy || model.snapshot?.watching == true)
                ForEach(model.snapshot?.recents ?? []) { record in
                    Button {
                        model.perform { await $0.reopen(record.id) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(record.pathSummary).lineLimit(2)
                            Text(
                                "\(record.media.rawValue) · \(record.volumeName ?? "unknown volume") · \(record.lastOpened.formatted())"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.busy || model.snapshot?.watching == true)
                }
            }
            Section("Probes") {
                Text(model.snapshot?.selected?.path ?? "Choose a folder or reopen a Recent.")
                    .font(.caption).textSelection(.enabled)
                TextField("Scenario / card label / filesystem", text: $model.scenario)
                Button("Read + capacity + read-only hints") { probe(write: false) }
                Button("Write small file + read back + remove") { probe(write: true) }
                Text(
                    "Writes use only clove-lab-folder-access/. Read-only and capacity values are hints; nil means unavailable. A write passes only after read-back."
                )
                .font(.caption)
                Button("Add up to 256 MiB fill file…", role: .destructive) { confirmFill = true }
                Button("Delete folder-access fill files…", role: .destructive) {
                    confirmCleanup = true
                }
                Text(
                    "Fill only a dedicated small test card or partition. Repeat to reach full; stop after the full error. Cleanup removes only folder-access UUID-named fill files."
                )
                .font(.caption)
            }
            .disabled(
                model.busy || model.snapshot?.selected == nil || model.snapshot?.watching == true)
            Section("Disconnect watch (foreground only)") {
                Button("Start disconnect watch") { model.startWatch() }
                    .disabled(
                        model.busy || model.snapshot?.selected == nil
                            || model.snapshot?.watching == true)
                Button("Mark: unplug now") { model.perform { await $0.markDisconnect() } }
                    .disabled(model.snapshot?.watching != true)
                Button("Stop watch") { model.stopWatch() }
                    .disabled(model.snapshot?.watching != true)
                Text(
                    "Mark immediately before pulling the test drive. Timing includes your delay before the pull. Polling runs every 500 ms plus call time. Presenter callbacks are recorded separately. Leaving this screen or backgrounding stops the watch."
                )
                .font(.caption)
            }
            Section("Report") {
                Button("Export S1 report") { export() }
                    .disabled(model.busy || model.snapshot == nil)
                if let exportName { Text(exportName).font(.caption).textSelection(.enabled) }
                if let error = session.exportError { Text(error).foregroundStyle(.red) }
                Text(
                    "Reports include paths and exact system errors. Review them before sharing. Export before force quit or reboot; Recents persist, the event log does not."
                )
                .font(.caption)
            }
            Section("Timestamped events") {
                if model.busy { ProgressView() }
                ForEach((model.snapshot?.events ?? []).reversed()) { event in
                    Text(event.summary).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("S1 · Folder access")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.probe.folder-access")
        .task { if model.snapshot == nil { await model.load() } }
        .onDisappear { model.stopWatch() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopWatch() } }
        .confirmationDialog(
            "Add up to 256 MiB to the selected test volume?", isPresented: $confirmFill
        ) {
            Button("Add fill file", role: .destructive) { model.perform { await $0.fill() } }
        } message: {
            Text(
                "Use a disposable small test card or partition. This can make other writes fail until you delete the fill files."
            )
        }
        .confirmationDialog(
            "Delete folder-access fill files in this folder?", isPresented: $confirmCleanup
        ) {
            Button("Delete folder-access fill files", role: .destructive) {
                model.perform { await $0.cleanFill() }
            }
        }
    }

    private func probe(write: Bool) {
        let scenario = model.scenario
        model.perform { await $0.probe(write: write, scenario: scenario) }
    }

    private func export() {
        guard let report = model.snapshot?.report else { return }
        // First ensure the Documents copy and footer are usable even if the tested volume is gone/full.
        guard let local = session.export(report) else { return }
        exportName = local.lastPathComponent
        if let folder = model.snapshot?.selected {
            do {
                try ReportExporter.write(report, toTestedFolder: folder)
            } catch {
                let event = AccessEvent(
                    .write, "Tested-folder report export failed; Documents fallback retained",
                    error: error)
                Task {
                    model.snapshot = await model.experiment.record(event)
                    if let final = model.snapshot?.report, let url = session.export(final) {
                        exportName = url.lastPathComponent
                    }
                }
            }
        }
    }
}
