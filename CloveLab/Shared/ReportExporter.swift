import Foundation
import SpikeSupport

/// Writes spike reports into the tested folder and into the app's Documents
/// folder, so a report survives a crash and also appears in Files.
enum ReportExporter {
    /// `clove-lab-<spike>-<UTC timestamp>.json`, for example
    /// `clove-lab-S2-20261113T101530Z.json`.
    static func fileName(spike: String, createdAt: Date) -> String {
        "clove-lab-\(spike)-\(timestamp(createdAt)).json"
    }

    /// Compact UTC timestamp, `20261113T101530Z`.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return formatter.string(from: date)
    }

    /// The app's Documents folder: "On My iPhone › Clove Lab" in Files.
    static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Writes `report` into Documents and, when given, into the tested folder.
    /// The returned URLs are in that order, so `first` is always the Documents
    /// copy.
    @discardableResult
    static func write(_ report: LabReport, toTestedFolder folder: URL? = nil) throws -> [URL] {
        let data = try report.encoded()
        let name = fileName(spike: report.spike, createdAt: report.createdAt)
        var written: [URL] = []

        if let documents = documentsDirectory {
            let url = documents.appendingPathComponent(name, isDirectory: false)
            try data.write(to: url, options: .atomic)
            written.append(url)
        }

        if let folder {
            let url = try SecurityScopedAccess.withAccess(to: folder) { folder in
                let url = folder.appendingPathComponent(name, isDirectory: false)
                try data.write(to: url, options: .atomic)
                return url
            }
            written.append(url)
        }

        return written
    }
}
