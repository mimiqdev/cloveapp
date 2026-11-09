import Foundation
import SpikeSupport

public struct EmbeddedWriteResult: Codable, Sendable {
    public var file: String
    public var control: String
    public var method: EmbeddedWriteMethod
    public var before: MetadataSnapshot?
    public var after: MetadataSnapshot?
    public var milliseconds: Double?
    public var error: String?
    public var failureLeftFileUnchanged: Bool?
    public var marksReadBack: Bool = false
    public var changedPaths: [String] = []
    public var changedExistingMetadata: [String] = []

    public var payloadUnchanged: Bool {
        guard let before, let after else { return false }
        return PayloadEvidence.contentMatches(before.payloads, after.payloads)
    }

    public var payloadRenumberedOnly: Bool {
        guard payloadUnchanged, let before, let after else { return false }
        return zip(before.payloads, after.payloads).contains {
            $0.sourceItemID != nil && $1.sourceItemID != nil && $0.sourceItemID != $1.sourceItemID
        }
    }

    public var seedDescription: String? {
        guard control == "seeded-other-app" else { return nil }
        return ["jpg", "jpeg"].contains((file as NSString).pathExtension.lowercased())
            ? "JPEG seed uses packet splice, preserving bytes outside XMP. This result compares against the seeded file; use camera-original rows for preservation against the camera original."
            : "Seed uses a native write that may already discard or normalize camera metadata. This seeded result does not show preservation against the camera original."
    }

    public var pixelsUnchanged: Bool {
        guard let before = before?.decodedPixels, let after = after?.decodedPixels else {
            return false
        }
        return before == after
    }

    public var losslessCandidate: Bool {
        error == nil && marksReadBack && payloadUnchanged && pixelsUnchanged
            && changedExistingMetadata.isEmpty && before?.makerNotes == after?.makerNotes
            && before?.imageCount == after?.imageCount
            && before?.jpegEXIFPreviews == after?.jpegEXIFPreviews
    }
}

public enum MetadataExperiment {
    /// One short pass over the four formats, with two write paths and a seeded
    /// preservation control. Every file is copied to a private temporary directory first.
    public static func run(folder: URL) throws -> (LabReport, [EmbeddedWriteResult]) {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            Set(["jpg", "jpeg", "dng"]).union(PhotoExtensions.heif).contains(
                $0.pathExtension.lowercased())
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            throw MetadataProbeError.invalid(
                "Choose a flat folder containing JPEG, HEIC/HEIF (.HIF) and DNG fixture copies.")
        }
        guard files.count <= 12 else {
            throw MetadataProbeError.invalid("Use a small fixture folder (at most 12 images).")
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "S4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var results: [EmbeddedWriteResult] = []
        for file in files {
            for method in EmbeddedWriteMethod.allCases {
                if method == .jpegXMPPacketSplice
                    && !["jpg", "jpeg"].contains(file.pathExtension.lowercased())
                {
                    continue
                }
                results.append(
                    probe(file: file, temporary: temporary, method: method, seeded: false))
                if method != .decodeAndAddImageAndMetadata {
                    results.append(
                        probe(file: file, temporary: temporary, method: method, seeded: true))
                }
            }
        }
        var measurements: [LabMeasurement] = []
        var notes = [
            "Writes use private copies; the picked files are never modified. Sibling temp + POSIX rename; no power-loss claim.",
            "HEIF follows pitm and ordered dimg references, comparing primary/grid, tile and auxiliary bytes by reference role and owner, plus reference topology. Item IDs are diagnostic only; renumbering is recorded separately from content changes. Exif/XMP items are excluded. Disconnected or ambiguous image graphs fail closed. DNG compares all strips/tiles and JPEG previews.",
            "Seeded results compare against the seeded file, not the camera original. JPEG seed uses packet splice to retain original non-XMP bytes. Other seeds use native writes and may already have lost MakerNotes or normalized EXIF before the measured write; their success does not show preservation against the camera original.",
            "JPEG packet splice is a bounded comparison path: standard single APP1 XMP only; extended/duplicate packets are rejected. Native copy may normalize unrelated EXIF/GPS values; changed paths are retained.",
            "Decoded comparison: ImageIO default image at index 0 rendered at native dimensions to sRGB 8-bit RGBA; not a separate RAW renderer.",
            "Clove Reject uses the spike-only namespace urn:clove:spike:s4:1.0/. Production namespace remains open for G1/S3.",
        ]
        #if os(macOS)
            notes.append(
                "macOS timings were taken on a shared, loaded host with other spike workers; one pass, not a benchmark."
            )
        #endif
        for result in results {
            let tags = [
                "file": result.file, "method": result.method.rawValue, "control": result.control,
            ]
            func record(_ name: String, _ value: Double, _ unit: String) {
                measurements.append(
                    LabMeasurement(name: name, value: value, unit: unit, tags: tags))
            }
            record("write-succeeded", result.error == nil ? 1 : 0, "bool")
            record("marks-read-back", result.marksReadBack ? 1 : 0, "bool")
            record("compressed-payload-unchanged", result.payloadUnchanged ? 1 : 0, "bool")
            record("heif-renumbered-only", result.payloadRenumberedOnly ? 1 : 0, "bool")
            if result.before != nil && result.after != nil {
                record("compressed-content-changed", result.payloadUnchanged ? 0 : 1, "bool")
            }
            if let seedDescription = result.seedDescription { notes.append(seedDescription) }
            record("decoded-pixels-unchanged", result.pixelsUnchanged ? 1 : 0, "bool")
            record("lossless-candidate", result.losslessCandidate ? 1 : 0, "bool")
            if let milliseconds = result.milliseconds { record("atomic-write", milliseconds, "ms") }
            if let before = result.before {
                record("file-before", Double(before.fileBytes), "bytes")
            }
            if let after = result.after, let before = result.before {
                record("file-after", Double(after.fileBytes), "bytes")
                record("file-size-delta", Double(after.fileBytes - before.fileBytes), "bytes")
            }
            if let unchanged = result.failureLeftFileUnchanged {
                record("failure-original-unchanged", unchanged ? 1 : 0, "bool")
            }
            // Keep the complete hashes, changed paths and errors inside the shared schema.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            notes.append(String(decoding: try encoder.encode(result), as: UTF8.self))
        }
        return (
            LabReport(
                spike: "S4",
                context: [
                    "folder": folder.lastPathComponent, "passes": "1", "files": String(files.count),
                ],
                measurements: measurements, notes: notes), results
        )
    }

    private static func probe(
        file: URL, temporary: URL, method: EmbeddedWriteMethod, seeded: Bool
    ) -> EmbeddedWriteResult {
        let working = temporary.appendingPathComponent(UUID().uuidString).appendingPathExtension(
            file.pathExtension)
        var result = EmbeddedWriteResult(
            file: file.lastPathComponent, control: seeded ? "seeded-other-app" : "camera-original",
            method: method)
        var originalHash: String?
        var writeClock: Stopwatch?
        do {
            try FileManager.default.copyItem(at: file, to: working)
            originalHash = PayloadDigest.hash(try Data(contentsOf: working))
            if seeded {
                writeClock = Stopwatch()
                try MetadataWriter.seedPreservationControl(at: working)
                writeClock = nil
            }
            let before = try MetadataSnapshot.read(working)
            result.before = before
            originalHash = before.fileSHA256
            if seeded && !before.preservationSeedPresent {
                throw MetadataProbeError.invalid(
                    "Seed did not retain all required sentinels; preservation is unproven")
            }
            let marks =
                seeded
                ? EmbeddedMarks(rating: -1, label: "Purple", rejected: false) : EmbeddedMarks()
            writeClock = Stopwatch()
            result.milliseconds = try MetadataWriter.write(
                to: working, method: method, marks: marks)
            writeClock = nil
            let after = try MetadataSnapshot.read(working)
            result.after = after
            result.marksReadBack = after.contains(marks)
            result.changedPaths = after.changedPaths(comparedTo: before)
            result.changedExistingMetadata = after.lostOrChangedExistingMetadata(comparedTo: before)
        } catch {
            if let writeClock { result.milliseconds = writeClock.seconds * 1000 }
            result.error = String(describing: error)
            if let originalHash, let current = try? Data(contentsOf: working) {
                result.failureLeftFileUnchanged = PayloadDigest.hash(current) == originalHash
            }
        }
        try? FileManager.default.removeItem(at: working)
        return result
    }
}
