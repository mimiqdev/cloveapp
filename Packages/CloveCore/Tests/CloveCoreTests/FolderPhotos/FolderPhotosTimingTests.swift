import Foundation
import Testing

@testable import CloveCore

/// Reports what holding a folder's photos costs on macOS when the scanner delivers 2,000 photos
/// in its 64-photo batches and each batch's metadata read lands before the next batch
/// (PRD P0-01, P0-03, G1 decision 3). It informs only, so it asserts no threshold.
@Suite("Folder photos timing")
struct FolderPhotosTimingTests {
    @Test func twoThousandPhotosInScannerBatchesTimingIsInformational() throws {
        let folder = FolderIdentity(rawValue: "folder-photos-timing")
        let total = 2_000
        let batchSize = 64
        let base = Date(timeIntervalSince1970: 1_760_000_000)

        /// One scanned RAW set, built the way the walk builds it.
        func item(_ index: Int) throws -> ScanItem {
            let path = "DCIM/10\(index % 3)XXXXX"
            let stem = String(format: "MMQ%05d", index)
            let url = URL(fileURLWithPath: "/photos/\(path)/\(stem).ARW")
            let set = try PhotoSet(folderID: folder, relativeFolderPath: path, rawURL: url)
            let file = try #require(PhotoFile(url: url))
            return .photo(
                ScannedPhotoSet(
                    photoSet: set, sidecar: .absent,
                    imageFiles: [
                        ScannedImageFile(file: file, size: 40 * 1024, modificationDate: base)
                    ]))
        }

        var photos = FolderPhotos()
        var index = 0
        var slowestBatch = 0.0
        let start = ContinuousClock.now
        while index < total {
            let end = min(index + batchSize, total)
            let batchStart = ContinuousClock.now
            let items = try (index..<end).map(item)
            let added = photos.insert(items)
            for photo in added {
                photos.setTime(
                    .known(
                        PhotoTime(
                            captureTime: base.addingTimeInterval(Double(index) * 0.4),
                            hasUTCOffset: true)),
                    for: photo.id)
            }
            slowestBatch = max(slowestBatch, milliseconds(batchStart.duration(to: .now)))
            index = end
        }
        let held = milliseconds(start.duration(to: .now))
        #expect(photos.count == total)

        let lookupStart = ContinuousClock.now
        var looked = 0
        for photo in photos.photos where photos.scannedSet(for: photo.id) != nil { looked += 1 }
        let lookups = milliseconds(lookupStart.duration(to: .now))
        #expect(looked == total)

        print(
            String(
                format: "Folder photos: macOS 2,000 scanned sets in 64-photo batches with their "
                    + "times, insert+time %.1f ms (slowest batch %.1f ms); "
                    + "identity-to-set lookups %.1f ms (informational)",
                held, slowestBatch, lookups))
    }
}
