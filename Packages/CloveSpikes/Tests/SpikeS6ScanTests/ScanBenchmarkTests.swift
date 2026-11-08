import Foundation
import Testing

@testable import SpikeS6Scan
import SpikeSupport

@Suite(.serialized)
struct ScanBenchmarkTests {
    @Test func suiteCoversEveryMethodKeySetAndStage() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTestTree.generated(in: container, fileTarget: 120)
        let report = try await ScanBenchmark.run(folder: tree.root, repetitions: 1)
        #expect(report.spike == "S6")
        #expect(report.schemaVersion == LabReport.currentSchemaVersion)
        #expect(report.context["fileSystem"] != nil)
        #expect(report.context["repetitions"] == "1")

        let methodCount = ScanMethod.allCases.count
        let keySetCount = ScanKeySet.allCases.count
        let scans = report.measurements.filter { $0.name == "list-elapsed" }
        #expect(scans.count == methodCount * keySetCount + methodCount)
        #expect(
            scans.filter { $0.tags["mode"] == "skip-rejected" }.count == methodCount * keySetCount)
        #expect(scans.filter { $0.tags["mode"] == "post-filter" }.count == methodCount)

        for method in ScanMethod.allCases {
            let matrix = scans.filter {
                $0.tags["method"] == method.tag && $0.tags["mode"] == "skip-rejected"
            }
            #expect(matrix.count == keySetCount)
            for measurement in matrix {
                #expect(measurement.value > 0)
                #expect(measurement.tags["pass"] == "1")
                #expect(measurement.tags["keys"] != nil)
            }
            let entries = report.measurements.filter {
                $0.name == "entries" && $0.tags["method"] == method.tag
            }
            #expect(entries.count == keySetCount)
            #expect(entries.allSatisfy { Int($0.value) == tree.photoFiles })

            let photos = report.measurements.filter {
                $0.name == "photos" && $0.tags["method"] == method.tag
            }
            #expect(photos.count == 1)
            #expect(Int(photos[0].value) == tree.photos)
            let pairs = report.measurements.filter {
                $0.name == "pairs" && $0.tags["method"] == method.tag
            }
            #expect(pairs.count == 1)
            #expect(Int(pairs[0].value) == tree.pairs)

            #expect(
                report.measurements.filter {
                    $0.name == "stat-elapsed" && $0.tags["method"] == method.tag
                }.count == 1)
            #expect(
                report.measurements.filter {
                    $0.name == "stream-batches" && $0.tags["method"] == method.tag
                }.count == 1)
            #expect(
                report.measurements.filter {
                    $0.name == "filter-elapsed" && $0.tags["method"] == method.tag
                }.count == 1)
        }

        let firstHundred = report.measurements.filter { $0.name == "first-100" }
        #expect(firstHundred.count == methodCount * keySetCount)
        #expect(firstHundred.allSatisfy { $0.value >= 0 })

        let data = try LabReport.makeEncoder().encode(report)
        let decoded = try LabReport.makeDecoder().decode(LabReport.self, from: data)
        // ISO 8601 drops sub-second precision, so compare the payload, not `createdAt`.
        #expect(decoded.spike == report.spike)
        #expect(decoded.schemaVersion == report.schemaVersion)
        #expect(decoded.measurements == report.measurements)
        #expect(decoded.context == report.context)
    }

    @Test func streamedBatchesArriveBeforeTheFullScanEnds() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTestTree.generated(in: container, fileTarget: 300)
        var options = ScanOptions()
        options.batchSize = 32
        for method in ScanMethod.allCases {
            let result = try await ScanStream.run(
                folder: tree.root, method: method, options: options)
            #expect(result.report.batches == (tree.photoFiles + 31) / 32)
            #expect(result.report.files == tree.photoFiles)
            let produced = try #require(result.report.firstBatchProducedMilliseconds)
            let received = try #require(result.report.firstBatchReceivedMilliseconds)
            let last = try #require(result.report.lastBatchReceivedMilliseconds)
            #expect(produced >= 0)
            #expect(received >= produced)
            #expect(last >= received)
            #expect(result.report.firstHundredMilliseconds != nil)
        }
    }

    /// Opt-in artifact collection for the report. `mise run verify` runs the
    /// functional tests above instead.
    ///
    /// ```sh
    /// CLOVE_S6_REPORT="$PWD/.build/s6/macOS.json" \
    ///   mise exec -- swift test --package-path Packages/CloveSpikes \
    ///   --filter ScanBenchmarkTests.collectReport
    /// ```
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["CLOVE_S6_REPORT"] != nil),
        .timeLimit(.minutes(20))
    )
    func collectReport() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CLOVE_S6_REPORT"])
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTree.makeTree(
            in: container,
            plan: ScanTreePlan(
                fileTarget: 2_000, folders: ScanTreePlan().folders, rejectsFileCount: 150,
                appleDoubleCount: 3, realisticSizes: true))
        var report = try await ScanBenchmark.run(folder: tree.root, repetitions: 3)
        report.context["treeFiles"] = String(tree.photoFiles)
        report.context["treePhotos"] = String(tree.photos)
        report.context["treePairs"] = String(tree.pairs)
        report.context["treeRejected"] = String(tree.rejectedFiles)
        report.context["treeBytes"] = String(tree.bytes)
        report.context["content"] =
            "placeholder bytes extended to plausible photo sizes with a sparse write on APFS"
        report.context["host"] = "macOS swift test, debug compilation"
        report.notes.append(
            "macOS numbers were taken on a shared, loaded host with other spike workers running.")
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: output)
        print("S6 macOS report: \(output.path)")
    }
}
