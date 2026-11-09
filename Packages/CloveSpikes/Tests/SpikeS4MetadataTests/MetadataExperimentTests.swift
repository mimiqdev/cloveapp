import Foundation
import SpikeSupport
import Testing

@testable import SpikeS4Metadata

@Suite(.serialized)
struct MetadataExperimentTests {
    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func fixtureWritesAndPreservation() throws {
        let folder = try #require(Fixtures.set("formats"))
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        .filter { ["jpg", "heic", "dng"].contains($0.pathExtension.lowercased()) }
        let originalHashes = try Dictionary(
            uniqueKeysWithValues: files.map { ($0, PayloadDigest.hash(try Data(contentsOf: $0))) })
        let (report, results) = try MetadataExperiment.run(folder: folder)
        #expect(results.count == 14)
        for result in results {
            print(
                "S4 \(result.file) \(result.control) \(result.method.rawValue): error=\(result.error ?? "none") payload=\(result.payloadUnchanged) pixels=\(result.pixelsUnchanged) marks=\(result.marksReadBack) candidate=\(result.losslessCandidate) ms=\(result.milliseconds ?? -1) delta=\(result.after.map { $0.fileBytes - (result.before?.fileBytes ?? 0) } ?? 0) changedExisting=\(result.changedExistingMetadata)"
            )
            if result.error != nil {
                #expect(result.failureLeftFileUnchanged == true)
            } else {
                #expect(result.before != nil)
                #expect(result.after != nil)
                #expect(result.marksReadBack)
                if result.method == .copyImageSource {
                    #expect(result.payloadUnchanged)
                    #expect(result.pixelsUnchanged)
                    #expect(result.before?.makerNotes == result.after?.makerNotes)
                    #expect(result.before?.imageCount == result.after?.imageCount)
                    #expect(result.before?.jpegEXIFPreviews == result.after?.jpegEXIFPreviews)
                    // Native JPEG copying normalizes some EXIF rationals/GPS. Keep that
                    // evidence visible rather than treating byte-identical pixels as preservation.
                    if result.file.lowercased().hasSuffix(".jpg") {
                        let observedNormalizations: Set<String> = [
                            "exif:ApertureValue", "exif:FocalPlaneXResolution",
                            "exif:FocalPlaneYResolution",
                            "exif:GPSAltitude", "exif:GPSLatitude", "exif:ShutterSpeedValue",
                            "exifEX:LensSpecification", "exifEX:LensSpecification[2]",
                            "exifEX:LensSpecification[3]",
                            "properties.{Exif}.ApertureValue",
                            "properties.{Exif}.ShutterSpeedValue",
                            "properties.{GPS}.Latitude",
                        ]
                        // Splice seeding leaves original IPTC intact. Native copy can
                        // reconcile its caption over the seeded XMP caption as well.
                        let seededCaptionChanges: Set<String> =
                            result.control == "seeded-other-app"
                            ? ["dc:description", "dc:description[x-default]"] : []
                        #expect(
                            Set(result.changedExistingMetadata).isSubset(
                                of: observedNormalizations.union(seededCaptionChanges))
                        )
                    } else {
                        #expect(result.changedExistingMetadata.isEmpty)
                    }
                    if result.control == "seeded-other-app" {
                        #expect(result.before?.preservationSeedPresent == true)
                        #expect(result.after?.preservationSeedPresent == true)
                    }
                }
            }
        }
        // Require both successful JPEG paths and the bounded splice's stronger metadata
        // preservation. Unsupported DNG must be a recorded error rather than a silent skip.
        let jpeg = results.filter {
            $0.file.lowercased().hasSuffix(".jpg") && $0.method == .copyImageSource
        }
        #expect(jpeg.count == 2)
        #expect(jpeg.allSatisfy { $0.error == nil && $0.payloadUnchanged && $0.pixelsUnchanged })
        let spliced = results.filter { $0.method == .jpegXMPPacketSplice }
        #expect(spliced.count == 2)
        #expect(spliced.allSatisfy { $0.losslessCandidate })
        for result in spliced {
            #expect(result.before?.jpegNonXMPBytes != nil)
            #expect(result.before?.jpegNonXMPBytes == result.after?.jpegNonXMPBytes)
        }
        let heic = results.filter {
            $0.file.lowercased().hasSuffix(".heic") && $0.method == .copyImageSource
        }
        #expect(heic.count == 2)
        #expect(heic.allSatisfy { $0.losslessCandidate })
        for (file, hash) in originalHashes {
            #expect(try PayloadDigest.hash(Data(contentsOf: file)) == hash)
        }
        if let path = ProcessInfo.processInfo.environment["S4_REPORT_PATH"] {
            try report.write(to: URL(fileURLWithPath: path))
            print("S4 report: \(path)")
        }
    }

    @Test func cameraHIFIsIncludedAndReportsExplainSeedLimitations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["camera.HIF", "second.hif"] {
            try Data("not an image".utf8).write(to: directory.appendingPathComponent(name))
        }
        let (report, results) = try MetadataExperiment.run(folder: directory)
        #expect(report.context["files"] == "2")
        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.error != nil && $0.failureLeftFileUnchanged == true })
        #expect(
            report.notes.contains {
                $0.contains("does not show preservation against the camera original")
            })
        #expect(
            results.filter { $0.control == "seeded-other-app" }.allSatisfy {
                $0.seedDescription != nil
            })
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func jpegSeedPreservesOriginalBytesOutsideXMP() throws {
        let folder = try #require(Fixtures.set("formats"))
        let source = folder.appendingPathComponent("canon-eos-6d.JPG")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("camera.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        let original = try Data(contentsOf: url)
        let originalMetadata = try MetadataSnapshot.read(url).metadata
        try MetadataWriter.seedPreservationControl(at: url)
        #expect(try JPEGPacket.nonXMPData(Data(contentsOf: url)) == JPEGPacket.nonXMPData(original))
        let seeded = try MetadataSnapshot.read(url)
        #expect(seeded.preservationSeedPresent)
        // Existing Camera Raw edits survive merging the seed packet.
        for (key, value) in originalMetadata where key.hasPrefix("crs:") {
            #expect(seeded.metadata[key] == value)
        }
    }

    @Test func interruptedCandidateLeavesOriginalAndSuccessfulRenameReplacesIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("photo.jpg")
        let original = Data("original".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) {
            try AtomicReplacement.write(to: url) { candidate in
                try Data("partial".utf8).write(to: candidate)
                throw MetadataProbeError.invalid("Injected failure after creating candidate")
            }
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["photo.jpg"])
        let replacement = Data("complete".utf8)
        try AtomicReplacement.write(to: url) { try replacement.write(to: $0) }
        #expect(try Data(contentsOf: url) == replacement)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["photo.jpg"])
    }

    @Test func failedWriteLeavesOriginalAndNoTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.jpg")
        let original = Data("not an image".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) {
            try MetadataWriter.write(to: url, method: .copyImageSource)
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["broken.jpg"])
    }
}
