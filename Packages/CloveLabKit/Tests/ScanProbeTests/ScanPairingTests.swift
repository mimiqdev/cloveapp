import Foundation
import Testing

@testable import ScanProbe

@Suite(.serialized)
struct ScanPairingTests {
    @Test func pairsRawAndJpegInTheSameFolder() throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        _ = try ScanTestTree.handmade(in: container)
        for method in ScanMethod.allCases {
            let listing = try ScanLister.list(folder: container, method: method, keySet: .all)
            let photos = ScanPairing.photos(from: listing.sortedByPath())
            #expect(photos.count == 11, "\(method.displayName) paired a different way")
            #expect(
                photos.map(\.baseName) == [
                    "IMG_0001", "IMG_0002", "IMG_0003", "IMG_0004", "IMG_0005", "IMG_0006",
                    "IMG_0007", "IMG_0008", "IMG_0008", "IMG_0001", "IMG_0002",
                ])

            let first = try #require(photos.first)
            #expect(first.relativeDirectory == "DCIM/100CANON")
            #expect(first.primary.pathExtension == "CR3")
            #expect(first.pairedJPEG?.pathExtension == "JPG")
            #expect(first.isPaired)

            let sameNameOtherFolder = try #require(
                photos.first {
                    $0.relativeDirectory == "DCIM/101CANON" && $0.baseName == "IMG_0001"
                })
            #expect(!sameNameOtherFolder.isPaired)
            #expect(sameNameOtherFolder.primary.pathExtension == "CR3")
            #expect(
                photos.contains {
                    $0.relativeDirectory == "DCIM/100CANON" && $0.baseName == "IMG_0006"
                        && $0.primary.pathExtension == "CR3" && !$0.isPaired
                })

            let standaloneJPEG = try #require(photos.first { $0.baseName == "IMG_0002" })
            #expect(!standaloneJPEG.isPaired)
            #expect(standaloneJPEG.primary.pathExtension == "JPG")

            let pairedLowercaseExtension = try #require(photos.first { $0.baseName == "IMG_0004" })
            #expect(pairedLowercaseExtension.primary.pathExtension == "CR3")
            #expect(pairedLowercaseExtension.pairedJPEG?.lastPathComponent == "IMG_0004.jpeg")

            let sony = try #require(photos.first { $0.baseName == "IMG_0007" })
            #expect(sony.primary.pathExtension == "ARW")
            #expect(sony.pairedJPEG?.pathExtension == "HIF")
            let triple = photos.filter { $0.baseName == "IMG_0008" }
            #expect(triple.count == 2)
            #expect(triple.first { $0.isPaired }?.pairedJPEG?.pathExtension == "JPG")
            #expect(triple.first { !$0.isPaired }?.primary.pathExtension == "hif")

            // The sidecar and the unsupported files are not photos.
            #expect(!photos.contains { $0.primary.pathExtension == "XMP" })
            #expect(!photos.contains { $0.primary.pathExtension == "MOV" })
            #expect(!photos.contains { $0.primary.pathExtension == "txt" })
            // The rejects folder is not listed, so nothing from it is paired.
            #expect(!photos.contains { $0.primary.path.contains("_Rejected") })
        }
    }

    @Test(arguments: ScanMethod.allCases)
    func sonyCameraFoldersPairEveryExtensionCaseAndSkipRejects(method: ScanMethod) throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let directory = "DCIM/100MSDCF"
        let extensionPairs = [("ARW", "HIF"), ("ARW", "hif"), ("arw", "HIF"), ("arw", "hif")]
        var expectedPaths: [String] = []
        for (index, extensions) in extensionPairs.enumerated() {
            let stem = "MMQ000\(index)"
            expectedPaths += [
                "\(directory)/\(stem).\(extensions.0)",
                "\(directory)/\(stem.lowercased()).\(extensions.1)",
            ]
        }
        expectedPaths += [
            "\(directory)/MMQ0004.arw", "\(directory)/mmq0004.jpg",
            "\(directory)/MMQ0005.ARW", "DCIM/101MSDCF/MMQ0005.hif",
            "\(directory)/_Rejected2/MMQ0006.HIF",
        ]
        let excludedPaths = [
            "_Rejected/DCIM/100MSDCF/MMQ0000.ARW",
            "_Rejected/DCIM/100MSDCF/mmq0000.HIF",
            "\(directory)/_Rejected/MMQ0004.arw",
            "\(directory)/_Rejected/mmq0004.hif",
            "\(directory)/._MMQ0000.HIF", "\(directory)/MMQ0000.XMP",
        ]
        for path in expectedPaths + excludedPaths {
            let url = container.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        for keys in [ScanKeySet.names, .nameTypeSizeModifiedDirectory] {
            let listing = try ScanLister.list(folder: container, method: method, keySet: keys)
            #expect(listing.entries.map(\.relativePath).sorted() == expectedPaths.sorted())
            #expect(listing.rejectedSkipped == 2)
            #expect(listing.errors == 0)
            let photos = ScanPairing.photos(from: listing.entries)
            #expect(photos.count == 8)
            #expect(photos.filter(\.isPaired).count == 5)
            for (index, extensions) in extensionPairs.enumerated() {
                let stem = "MMQ000\(index)"
                let photo = try #require(photos.first { $0.baseName == stem })
                #expect(photo.relativeDirectory == directory)
                #expect(photo.primary.lastPathComponent == "\(stem).\(extensions.0)")
                #expect(
                    photo.pairedJPEG?.lastPathComponent == "\(stem.lowercased()).\(extensions.1)")
            }
            let jpegPair = try #require(photos.first { $0.baseName == "MMQ0004" })
            #expect(jpegPair.primary.pathExtension == "arw")
            #expect(jpegPair.pairedJPEG?.lastPathComponent == "mmq0004.jpg")
            #expect(photos.filter { $0.baseName == "MMQ0005" }.allSatisfy { !$0.isPaired })
            #expect(
                photos.contains {
                    $0.relativeDirectory == "\(directory)/_Rejected2" && !$0.isPaired
                })
        }
    }

    @Test func pairingUsesTheListingWithoutTouchingTheDisk() throws {
        let entries = [
            entry("DCIM/100CANON/IMG_0001.CR3"),
            entry("DCIM/100CANON/IMG_0001.JPG"),
            entry("DCIM/100CANON/IMG_0002.JPG"),
            entry("DCIM/101CANON/IMG_0001.JPG"),
        ]
        let photos = ScanPairing.photos(from: entries)
        #expect(photos.count == 3)
        #expect(photos.filter(\.isPaired).count == 1)
    }

    @Test func aSecondRawWithTheSameBaseNameStaysItsOwnPhoto() throws {
        let entries = [
            entry("DCIM/100CANON/IMG_0001.CR3"),
            entry("DCIM/100CANON/IMG_0001.DNG"),
            entry("DCIM/100CANON/IMG_0001.JPG"),
        ]
        let photos = ScanPairing.photos(from: entries)
        #expect(photos.count == 2)
        #expect(photos.filter(\.isPaired).count == 1)
        #expect(photos.first { $0.isPaired }?.primary.pathExtension == "CR3")
    }

    @Test func heifPairingIsCaseInsensitiveAndNeverCrossesFolders() {
        let entries = [
            entry("a/sony.ARW"), entry("a/SONY.HiF"), entry("b/sony.ARW"),
            entry("c/sony.hif"), entry("a/triple.ARW"), entry("a/triple.HIF"),
            entry("a/triple.JPG"),
        ]
        let forward = ScanPairing.photos(from: entries)
        let reversed = ScanPairing.photos(from: entries.reversed())
        #expect(forward == reversed)
        #expect(forward.count == 5)
        #expect(forward.filter(\.isPaired).count == 2)
        #expect(
            forward.first { $0.baseName == "sony" }?.pairedJPEG?.lastPathComponent == "SONY.HiF")
        #expect(forward.filter { $0.relativeDirectory != "a" }.allSatisfy { !$0.isPaired })
    }

    @Test func photosAreOrderedByFolderThenBaseName() {
        let entries = [
            entry("DCIM/101CANON/IMG_0002.JPG"),
            entry("DCIM/100CANON/IMG_0003.JPG"),
            entry("DCIM/100CANON/IMG_0001.JPG"),
        ]
        let photos = ScanPairing.photos(from: entries)
        #expect(
            photos.map(\.relativeDirectory) == ["DCIM/100CANON", "DCIM/100CANON", "DCIM/101CANON"])
        #expect(photos.map(\.baseName) == ["IMG_0001", "IMG_0003", "IMG_0002"])
    }

    @Test func removingRejectedUsesTheConfiguredFolderName() {
        let entries = [
            entry("DCIM/100CANON/IMG_0001.JPG"),
            entry("DCIM/100CANON/_Rejected/IMG_9000.JPG"),
            entry("DCIM/_Rejected/IMG_9001.JPG"),
            entry("DCIM/100CANON/_Rejected2/IMG_9002.JPG"),
        ]
        let kept = ScanPairing.removingRejected(entries)
        #expect(
            kept.map(\.relativePath) == [
                "DCIM/100CANON/IMG_0001.JPG", "DCIM/100CANON/_Rejected2/IMG_9002.JPG",
            ])
        #expect(ScanPairing.removingRejected(entries, folderName: "_Rejected2").count == 3)
    }

    private func entry(_ relativePath: String) -> ScanEntry {
        ScanEntry(
            url: URL(fileURLWithPath: "/tmp/scan/" + relativePath),
            relativePath: relativePath)
    }
}

@Suite(.serialized)
struct ScanVolumeTests {
    @Test func describesTheTemporaryVolume() throws {
        let container = try ScanTestTree.container()
        defer { try? FileManager.default.removeItem(at: container) }
        let description = ScanVolume.describe(container)
        #expect(description["fileSystem"]?.isEmpty == false)
        #expect(description["volume"]?.isEmpty == false)
    }
}
