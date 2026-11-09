import Foundation
import Observation
import LabSupport

/// State shared by the Clove Lab screens: the last exported report and any
/// export error. Inject it with `.environment(_:)`.
@Observable
@MainActor
final class LabSession {
    /// Most recent report written by any probe; the footer shares this file.
    private(set) var lastReportURL: URL?

    /// Why the last export failed, if it did.
    private(set) var exportError: String?

    nonisolated init() {}

    /// Writes `report` into the tested folder (when given) and into Documents,
    /// and remembers the Documents copy for the footer.
    @discardableResult
    func export(_ report: LabReport, toTestedFolder folder: URL? = nil) -> URL? {
        do {
            let written = try ReportExporter.write(report, toTestedFolder: folder)
            exportError = written.isEmpty ? "The Documents folder is unavailable." : nil
            lastReportURL = written.first
            return lastReportURL
        } catch {
            exportError = error.localizedDescription
            return nil
        }
    }

    /// Writes a device report on first launch, so the footer has a real file to
    /// share before a probe records any measurements.
    func prepareDeviceReportIfNeeded() {
        guard lastReportURL == nil else { return }
        export(LabReport(spike: "S0", notes: ["Device report from Clove Lab."]))
    }
}
