import Foundation
import Testing

@testable import CloveCore

/// The macOS timing run from issue #47. It reports numbers and gates nothing:
/// S6 measured 3–8 ms to the first batch and about 35 ms for 2,000 files.
@Suite(.serialized)
struct FolderScanTimingTests {
    @Test(.timeLimit(.minutes(10)))
    func twoThousandFilesReportTimeToFirstBatchAndTotalTime() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        let plan = try GeneratedScanFolder.write(in: folder)
        #expect(plan.fileCount == 2_000)
        #expect(plan.photoCount == 1_482)

        let clock = ContinuousClock()
        let start = clock.now
        let scan = FolderScan(
            folderURL: folder.url, folderID: FolderIdentity(rawValue: "scan-timing"))
        var firstBatchMilliseconds: Double?
        var batchCount = 0
        for try await batch in scan {
            batchCount += 1
            if firstBatchMilliseconds == nil {
                firstBatchMilliseconds = Self.milliseconds(from: start, to: clock.now)
            }
        }
        let summary = try await scan.summary()
        let totalMilliseconds = Self.milliseconds(from: start, to: clock.now)
        let first = try #require(firstBatchMilliseconds)

        print(
            """
            scan timing (2,000 files, 1,482 photos, macOS debug build):
              time to first batch: \(Self.format(first)) ms
              total scan time:     \(Self.format(totalMilliseconds)) ms
              batches:             \(batchCount) of at most \(ScanConfiguration.maximumBatchSize) items
            """
        )

        // Only the counts are a gate; the timings above inform the PR and later milestones.
        #expect(summary.logicalPhotoCount == 1_482)
        #expect(summary.status == .complete)
        #expect(summary.unsupportedFileCount == 2)
        #expect(summary.skippedFolderCount == 2)
        #expect(first <= totalMilliseconds)
        #expect(batchCount > 0)
    }

    /// Milliseconds between two instants, for the report above.
    private static func milliseconds(
        from start: ContinuousClock.Instant, to end: ContinuousClock.Instant
    ) -> Double {
        let parts = start.duration(to: end).components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    /// One decimal place is enough for a number that informs and does not gate.
    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}

/// What the generated timing tree contains.
struct GeneratedScanPlan {
    /// Photo files written below `DCIM`, with a pair counting as two.
    let fileCount: Int
    /// Logical photos the scanner should pair from them.
    let photoCount: Int
}

/// Writes the 2,000-file tree the timing test scans: six DCIM folders, RAW+JPEG pairs,
/// standalone RAW/JPEG/HEIF files, and the card junk the filters must leave out.
enum GeneratedScanFolder {
    /// Folder names, one per Sony-style camera folder.
    static let folderNames = [
        "100CANON", "101CANON", "102NIKON", "103SONY", "104FUJI", "105PANASONIC",
    ]
    /// RAW+JPEG pairs, each counted as two files.
    static let pairCount = 518
    /// Standalone photos in addition to the pairs.
    static let standaloneCount = 964
    /// RAW extensions cycled through the tree (PRD Supported files).
    static let rawExtensions = ["CR3", "NEF", "ARW", "RAF", "ORF", "RW2", "DNG"]

    /// Writes the tree below `folder` and returns what it should scan to.
    @discardableResult
    static func write(in folder: ScanTestFolder) throws -> GeneratedScanPlan {
        for index in 0..<pairCount {
            let directory = "DCIM/\(folderNames[index % folderNames.count])"
            let stem = String(format: "IMG_%05d", index)
            try folder.file("\(directory)/\(stem).\(rawExtensions[index % rawExtensions.count])")
            try folder.file("\(directory)/\(stem).JPG")
        }
        for index in 0..<standaloneCount {
            let directory = "DCIM/\(folderNames[index % folderNames.count])"
            let stem = String(format: "STD_%05d", index)
            switch index % 5 {
            case 0, 1, 2:
                try folder.file("\(directory)/\(stem).JPG")
            case 3:
                try folder.file("\(directory)/\(stem).HEIC")
            default:
                try folder.file(
                    "\(directory)/\(stem).\(rawExtensions[index % rawExtensions.count])")
            }
        }
        // Junk the walk must ignore: AppleDouble files, hidden files, a rejects folder,
        // unsupported files and a package.
        for (index, name) in folderNames.enumerated() {
            try folder.file("DCIM/\(name)/._IMG_0000\(index).CR3")
            try folder.file("DCIM/\(name)/.DS_Store")
        }
        for index in 0..<20 {
            try folder.file("DCIM/100CANON/_Rejected/IMG_9\(index).JPG")
        }
        try folder.file("DCIM/100CANON/MVI_0001.MOV")
        try folder.file("DCIM/100CANON/NOTES.txt")
        try folder.file("Photos.photoslibrary/DCIM/Inside.JPG")
        return GeneratedScanPlan(
            fileCount: pairCount * 2 + standaloneCount,
            photoCount: pairCount + standaloneCount)
    }
}
