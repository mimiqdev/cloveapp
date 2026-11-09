#if CLOVE_SCAN_LOCAL_RUNNER
    import Foundation
    import ScanProbe
    import LabSupport

    /// Compile separately with `-D CLOVE_SCAN_LOCAL_RUNNER` for the Mac or the iOS
    /// Simulator, the way the Folder access runner is built. Arguments: an existing report
    /// output directory, and an optional file count (default 2,000).
    ///
    /// The tree is built below the process's temporary directory and removed
    /// afterwards; the report is written to the output directory. A simulator
    /// process reads the Mac's SSD through its own sandbox, so its numbers are
    /// functional evidence, not card-reader numbers.
    @main
    struct ScanLocalRunner {
        static func main() async throws {
            let arguments = CommandLine.arguments
            guard arguments.count >= 2 else {
                print("usage: runner <report-output-directory> [file-count]")
                return
            }
            let outputDirectory = URL(fileURLWithPath: arguments[1])
            let fileTarget = arguments.count >= 3 ? Int(arguments[2]) ?? 2_000 : 2_000
            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "clove-scan-local-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(
                at: container, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: container) }

            let tree = try await ScanTree.makeTree(
                in: container,
                plan: ScanTreePlan(
                    fileTarget: fileTarget, folders: ScanTreePlan().folders,
                    rejectsFileCount: 150, appleDoubleCount: 3, realisticSizes: true))
            var report = try await ScanBenchmark.run(folder: tree.root, repetitions: 3)
            report.context["treeFiles"] = String(tree.photoFiles)
            report.context["treePhotos"] = String(tree.photos)
            report.context["treePairs"] = String(tree.pairs)
            report.context["treeRejected"] = String(tree.rejectedFiles)
            report.context["treeBytes"] = String(tree.bytes)
            report.context["content"] = "sparse files with plausible photo sizes"
            report.context["execution"] = "standalone runner, debug compiler settings"
            #if os(iOS)
                report.notes.append(
                    "iOS Simulator process on the shared, loaded Mac host; not a physical device.")
            #else
                report.notes.append(
                    "macOS numbers taken on a shared, loaded host with other spike workers running."
                )
            #endif

            let timestamp = ISO8601DateFormatter()
            timestamp.timeZone = TimeZone(secondsFromGMT: 0)
            timestamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
            let output = outputDirectory.appendingPathComponent(
                "clove-lab-S6-\(timestamp.string(from: report.createdAt)).json")
            try report.write(to: output)
            print("Scan report: \(output.path)")
        }
    }
#endif
