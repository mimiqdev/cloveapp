import Foundation
import Observation
import FoldStateProbe

/// Keep the event history across view/scene recreation, including older state
/// IDs and counters. This file is a working journal, not the shared export.
@MainActor
@Observable
final class FoldStateJournal {
    private(set) var log: DuoLog
    private(set) var error: String?
    private let url: URL?

    init() {
        url = ReportExporter.documentsDirectory?.appendingPathComponent(
            "fold-state-working-journal.json")
        log = DuoLog()
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do {
                log = try JSONDecoder().decode(DuoLog.self, from: Data(contentsOf: url))
            } catch {
                self.error = "Could not restore Fold state journal: \(error.localizedDescription)"
            }
        }
    }

    func record(_ snapshot: DuoSnapshot, reason: String, force: Bool = false) {
        guard log.record(snapshot, reason: reason, force: force) else { return }
        save()
    }

    func start() {
        log = DuoLog()
        save()
    }

    private func save() {
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            try JSONEncoder().encode(log).write(to: url, options: .atomic)
            error = nil
        } catch {
            self.error = "Fold state journal could not be saved: \(error.localizedDescription)"
        }
    }
}
