import Foundation
import Testing

@testable import ScanProbe

@Suite(.serialized)
struct ScanRuleTests {
    @Test func photoExtensionsCoverTheSupportedFiles() {
        for name in [
            "IMG_0001.CR3", "IMG_0002.NEF", "IMG_0003.ARW", "IMG_0004.RAF", "a.ORF",
            "b.RW2", "c.DNG", "d.JPG", "e.JPEG", "f.HEIC", "g.heif",
        ] {
            #expect(ScanRule.isPhotoFile(name), "\(name) should be a photo")
        }
        for name in ["IMG_0001.XMP", "MVI_0001.MOV", "NOTES.txt", ".DS_Store"] {
            #expect(!ScanRule.isPhotoFile(name), "\(name) should not be a photo")
        }
        // Hidden names are filtered separately; `._IMG_0001.CR3` keeps its
        // extension but never reaches the pairing step.
        #expect(ScanRule.isPhotoFile("._IMG_0001.CR3"))
        #expect(ScanRule.isHidden("._IMG_0001.CR3"))
    }

    @Test func hiddenFilesIncludeAppleDoubleAndDotFiles() {
        #expect(ScanRule.isHidden("._IMG_0001.CR3"))
        #expect(ScanRule.isHidden(".DS_Store"))
        #expect(ScanRule.isHidden(".Trashes"))
        #expect(!ScanRule.isHidden("_Rejected"))
        #expect(!ScanRule.isHidden("IMG_0001.CR3"))
    }

    @Test func keySetsRequestTheExpectedKeys() {
        #expect(ScanKeySet.names.keys.isEmpty)
        #expect(ScanKeySet.all.keys.count == 6)
        #expect(
            Set(ScanKeySet.all.keys).isSuperset(
                of: Set(ScanKeySet.nameTypeSizeModifiedDirectory.keys)))
        #expect(ScanKeySet.size.keys == [.fileSizeKey])
        #expect(ScanKeySet.modified.keys == [.contentModificationDateKey])
        #expect(ScanKeySet.contentType.keys == [.contentTypeKey])
        #expect(ScanKeySet.all.rawValue == "all")
    }
}

@Suite(.serialized)
struct ScanTreeTests {
    @Test func generatorWritesACardShapedTreeAndRemovesIt() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let summary = try await ScanTestTree.generated(
            in: container, fileTarget: 200, rejectsFileCount: 10)
        #expect(summary.photoFiles == 200)
        #expect(summary.pairs > 0)
        #expect(summary.photos == 200 - summary.pairs)
        #expect(summary.rejectedFiles == 10)
        #expect(summary.folders == 2)

        let tree = ScanTree.treeURL(in: container)
        #expect(ScanTree.exists(in: container))
        #expect(
            FileManager.default.fileExists(
                atPath: tree.appendingPathComponent("DCIM/100CANON").path))
        #expect(
            FileManager.default.fileExists(
                atPath: tree.appendingPathComponent("DCIM/100CANON/_Rejected/IMG_9000.JPG").path))
        #expect(
            FileManager.default.fileExists(
                atPath: tree.appendingPathComponent("DCIM/101CANON/MVI_0001.MOV").path))
        #expect(
            FileManager.default.fileExists(
                atPath: tree.appendingPathComponent("DCIM/100CANON/._IMG_1001.CR3").path))
        #expect(
            FileManager.default.fileExists(
                atPath: tree.appendingPathComponent("DCIM/100CANON/.Trashes/IMG_0105.JPG").path))

        let expected = try ScanTestTree.expectedPhotoFiles(in: tree, rejects: "_Rejected")
        #expect(expected.count == summary.photoFiles)

        #expect(try ScanTree.removeTree(in: container))
        #expect(!ScanTree.exists(in: container))
        #expect(try !ScanTree.removeTree(in: container))
    }

    @Test func generatorReplacesAnExistingTreeAndHonoursTheQuota() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        _ = try await ScanTestTree.generated(in: container, fileTarget: 33, folders: ["100CANON"])
        let second = try await ScanTestTree.generated(
            in: container, fileTarget: 47, folders: ["100CANON", "101CANON"])
        #expect(second.photoFiles == 47)
        let files = try ScanTestTree.expectedPhotoFiles(in: ScanTree.treeURL(in: container))
        #expect(files.count == 47)
    }

    @Test func removalRefusesAFolderThatIsNotTheGeneratedTree() throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let other = container.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        #expect(throws: ScanTreeFailure.self) {
            try ScanTree.removeTree(at: other)
        }
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func realisticSizesOnlyExtendFilesWhenAsked() async throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let tree = try await ScanTree.makeTree(
            in: container,
            plan: ScanTreePlan(
                fileTarget: 20, folders: ["100CANON"], rejectsFileCount: 1,
                realisticSizes: true))
        let file = try #require(
            try ScanTestTree.expectedPhotoFiles(in: tree.root)
                .first { $0.hasSuffix(".CR3") }
                .map { tree.root.appendingPathComponent($0) })
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > ScanTree.placeholderBytes)
    }
}
