import Foundation
import Testing

@testable import CloveCore

/// Locates the shared fixture sets that `scripts/make-fixture-sets` builds outside the
/// repository. A machine without them skips these tests instead of failing.
enum ScanFixtures {
    /// Environment variable that overrides the cache location.
    static let directoryEnvironmentVariable = "CLOVE_FIXTURES_DIR"

    /// The cache's default location, next to the project on the T7 SSD.
    static let defaultDirectory = URL(
        fileURLWithPath: "/Volumes/T7/Projects/.clove-fixtures", isDirectory: true)

    /// The cache directory, with `$CLOVE_FIXTURES_DIR` winning when set.
    static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[directoryEnvironmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return defaultDirectory
    }

    /// `sets/<name>` in the cache, or nil when the set has not been built.
    static func set(_ name: String) -> URL? {
        let url = directory()
            .appendingPathComponent("sets", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue ? url : nil
    }
}

/// Scans the standard fixture sets, which are real camera files rather than generated stubs.
@Suite(.serialized)
struct FolderScanFixturesTests {
    @Test(.enabled(if: ScanFixtures.set("card-basic") != nil))
    func cardBasicFindsEveryLogicalPhotoAndSkipsTheCardJunk() async throws {
        let set = try #require(ScanFixtures.set("card-basic"))
        let outcome = try await scanFixture(set, id: "fixture-card-basic")
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 10)
        #expect(outcome.photos.count == 10)
        #expect(summary.unsupportedFileCount == 2)
        #expect(
            Set(summary.unsupportedFiles.map(\.lastPathComponent))
                == Set(["MVI_0006.MOV", "NOTES.txt"]))
        #expect(summary.ambiguousCount == 0)
        #expect(summary.orphanSidecarCount == 0)
        #expect(summary.skippedFolderCount == 1)
        #expect(summary.status == .complete)

        let byFolder = Dictionary(
            grouping: outcome.photos, by: { $0.photoSet.id.relativeFolderPath })
        #expect(byFolder["DCIM/100CANON"]?.count == 5)
        #expect(byFolder["DCIM/101CANON"]?.count == 5)

        let first = try #require(outcome.photos.first { $0.photoSet.id.stem == "img_0001" })
        #expect(first.photoSet.primary.url.lastPathComponent == "IMG_0001.CR3")
        #expect(first.photoSet.jpegCompanion?.url.lastPathComponent == "IMG_0001.JPG")
        #expect(first.photoSet.heifCompanion == nil)
        #expect(first.sidecar == .absent)

        let jpegOnly = try #require(
            outcome.photos.first {
                $0.photoSet.id.relativeFolderPath == "DCIM/100CANON"
                    && $0.photoSet.id.stem == "img_0003"
            })
        #expect(jpegOnly.photoSet.primary.format == .jpeg)

        let heifOnly = try #require(
            outcome.photos.first { $0.photoSet.id.stem == "img_0004" })
        #expect(heifOnly.photoSet.primary.url.lastPathComponent == "IMG_0004.HEIC")
        #expect(heifOnly.photoSet.primary.format == .heif)

        // `.XMP` is reused with its actual spelling; the DNG stays a RAW photo.
        let sidecar = try #require(outcome.photos.first { $0.photoSet.id.stem == "img_0104" })
        #expect(sidecar.photoSet.primary.url.lastPathComponent == "IMG_0104.DNG")
        #expect(sidecar.photoSet.primary.format == .raw)
        #expect(
            sidecar.sidecar
                == .resolved(
                    set.appendingPathComponent("DCIM/101CANON/IMG_0104.XMP")))
        #expect(
            sidecar.photoSet.markPersistence.rating
                == .xmpSidecar(set.appendingPathComponent("DCIM/101CANON/IMG_0104.XMP")))

        // The rejects folder and the hidden `.Trashes` folder contribute nothing.
        #expect(!outcome.photos.contains { $0.photoSet.id.stem == "img_9000" })
        #expect(!outcome.photos.contains { $0.photoSet.id.stem == "img_0105" })
    }

    @Test(.enabled(if: ScanFixtures.set("name-collision") != nil))
    func nameCollisionKeepsActivePhotosAndSkipsBothRejectsFolders() async throws {
        let set = try #require(ScanFixtures.set("name-collision"))
        let outcome = try await scanFixture(set, id: "fixture-name-collision")
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 4)
        #expect(summary.unsupportedFileCount == 0)
        #expect(summary.skippedFolderCount == 2)
        #expect(summary.ambiguousCount == 0)
        #expect(summary.orphanSidecarCount == 0)
        #expect(summary.status == .complete)

        let first = try #require(outcome.photos.first { $0.photoSet.id.stem == "img_0001" })
        #expect(first.photoSet.primary.url.lastPathComponent == "IMG_0001.CR3")
        #expect(first.photoSet.jpegCompanion?.url.lastPathComponent == "IMG_0001.JPG")
        #expect(
            first.sidecar == .resolved(set.appendingPathComponent("DCIM/100CANON/IMG_0001.XMP")))
        #expect(
            Set(outcome.photos.map(\.photoSet.id.relativeFolderPath))
                == Set(["DCIM/100CANON", "DCIM/101CANON"]))
    }

    @Test(.enabled(if: ScanFixtures.set("formats") != nil))
    func formatsYieldsOnePhotoPerCameraFile() async throws {
        let set = try #require(ScanFixtures.set("formats"))
        let outcome = try await scanFixture(set, id: "fixture-formats")
        let summary = try #require(outcome.summary)
        // The Sony ARW and HEIC share a stem, so they are one RAW+HIF photo (G1 decision 1).
        #expect(summary.logicalPhotoCount == 9)
        #expect(summary.unsupportedFileCount == 0)
        #expect(summary.ambiguousCount == 0)
        #expect(summary.orphanSidecarCount == 0)
        #expect(summary.skippedFolderCount == 0)
        #expect(summary.status == .complete)

        let formats = outcome.photos.reduce(into: [PhotoFormat: Int]()) { counts, photo in
            counts[photo.photoSet.primary.format, default: 0] += 1
        }
        #expect(formats[.raw] == 8)
        #expect(formats[.jpeg] == 1)
        #expect(formats[.heif] == nil)
        let sony = try #require(outcome.photos.first { $0.photoSet.id.stem == "sony-ilce-7s" })
        #expect(sony.photoSet.primary.url.lastPathComponent == "sony-ilce-7s.ARW")
        #expect(sony.photoSet.heifCompanion?.url.lastPathComponent == "sony-ilce-7s.HEIC")
        #expect(outcome.photos.allSatisfy { $0.photoSet.id.relativeFolderPath.isEmpty })
        #expect(outcome.photos.allSatisfy { $0.sidecar == .absent })
    }
}

/// Scans one fixture set and collects its batches and summary.
private func scanFixture(_ set: URL, id: String) async throws -> ScanOutcome {
    let scan = FolderScan(folderURL: set, folderID: FolderIdentity(rawValue: id))
    var outcome = ScanOutcome()
    for try await batch in scan {
        outcome.batches.append(batch)
    }
    outcome.summary = try await scan.summary()
    return outcome
}
