import Darwin
import Foundation
import SpikeSupport

public enum XMPAtomicMethod: String, CaseIterable, Sendable {
    case replaceItemAt
    case rename
}

public enum XMPAtomicWriter {
    /// Returns the staging URL even on successful replacement, for residue checks.
    /// The caller owns a scratch directory; never call this against user originals.
    @discardableResult
    public static func write(
        _ data: Data, to destination: URL, method: XMPAtomicMethod, coordinated: Bool
    ) throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw XMPError.invalidPacket("Replacement destination must be a regular file")
            }
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".s3-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            func replace(_ target: URL) throws {
                switch method {
                case .replaceItemAt:
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
                case .rename:
                    let status = Darwin.rename(temporary.path, target.path)
                    guard status == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
            }
            if coordinated {
                var coordinationError: NSError?
                var replacementError: Error?
                NSFileCoordinator(filePresenter: nil).coordinate(
                    writingItemAt: destination, options: .forReplacing, error: &coordinationError
                ) { target in
                    do { try replace(target) } catch { replacementError = error }
                }
                if let coordinationError { throw coordinationError }
                if let replacementError { throw replacementError }
            } else {
                try replace(destination)
            }
            return temporary
        } catch {
            // A failed attempt must not leave our staging files on the card.
            // The suite also inventories the directory to detect cleanup failure.
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

public enum XMPSuite {
    public static let requested = XMPMarks(rating: 3, label: "Green", reject: true)

    public static func fileSystem(at folder: URL) -> String {
        var info = statfs()
        let descriptor = Darwin.open(folder.path, O_RDONLY)
        guard descriptor >= 0 else { return "unknown (open errno \(errno))" }
        defer { Darwin.close(descriptor) }
        guard Darwin.fstatfs(descriptor, &info) == 0 else {
            return "unknown (fstatfs errno \(errno))"
        }
        return withUnsafeBytes(of: info.f_fstypename) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// All writes are confined to an exclusively created clove-lab-s3 directory.
    /// Failures (including directory creation and cleanup) still produce a report.
    public static func run(in folder: URL) -> LabReport {
        var report = LabReport(
            spike: "S3",
            context: [
                "fileSystem": fileSystem(at: folder), "folder": folder.lastPathComponent,
                "suite": "s3-v1", "fixtureCount": String(XMPFixtures.packets.count),
                "coordination": "both uncoordinated and NSFileCoordinator",
            ])
        let scratch = folder.appendingPathComponent("clove-lab-s3", isDirectory: true)
        var owned = false
        do {
            let status = Darwin.mkdir(scratch.path, 0o700)
            guard status == 0 else {
                if errno == EEXIST { throw XMPError.unsafeFolder }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            owned = true
            for (fixture, data) in XMPFixtures.packets.sorted(by: { $0.key < $1.key }) {
                let copy = scratch.appendingPathComponent(fixture)
                try data.write(to: copy, options: .withoutOverwriting)
                for approach in XMPApproach.allCases {
                    let copied = try Data(contentsOf: copy)
                    report.measurements += roundTrip(copied, fixture: fixture, approach: approach)
                    if let output = try? approach.write(copied, marks: requested) {
                        let destination = scratch.appendingPathComponent(
                            "\(approach.rawValue)-\(fixture)")
                        try output.write(to: destination, options: .withoutOverwriting)
                        let readBack = try Data(contentsOf: destination)
                        let valid = (try? XMPInspection.inspect(readBack)) == requested
                        report.measurements.append(
                            .init(
                                name: "disk-marks-confirmed", value: valid ? 1 : 0, unit: "bool",
                                tags: ["fixture": fixture, "approach": approach.rawValue]))
                    }
                }
            }
            for approach in XMPApproach.allCases {
                let newSidecar = scratch.appendingPathComponent("new-\(approach.rawValue).xmp")
                let output = try approach.write(Data(), marks: requested)
                try output.write(to: newSidecar, options: .withoutOverwriting)
                let readBack = try Data(contentsOf: newSidecar)
                let valid = try XMPInspection.inspect(readBack) == requested
                let wrapped = String(decoding: readBack, as: UTF8.self).contains("<?xpacket begin=")
                report.measurements.append(
                    .init(
                        name: "new-sidecar-valid", value: valid ? 1 : 0, unit: "bool",
                        tags: ["approach": approach.rawValue]))
                report.measurements.append(
                    .init(
                        name: "new-sidecar-packet-wrapper", value: wrapped ? 1 : 0, unit: "bool",
                        tags: ["approach": approach.rawValue]))
            }
            for method in XMPAtomicMethod.allCases {
                for coordinated in [false, true] {
                    for iteration in 0..<3 {
                        let target = scratch.appendingPathComponent("atomic.xmp")
                        guard let original = XMPFixtures.packets["lightroom-full.xmp"] else {
                            throw XMPError.invalidPacket("Bundled Lightroom fixture missing")
                        }
                        try original.write(to: target)
                        let output = try XMPApproach.preservingEdit.write(
                            original, marks: requested)
                        let tags = [
                            "method": method.rawValue, "coordinated": String(coordinated),
                            "iteration": String(iteration),
                        ]
                        let timer = Stopwatch()
                        do {
                            let temporary = try XMPAtomicWriter.write(
                                output, to: target, method: method, coordinated: coordinated)
                            let elapsed = timer.seconds * 1000
                            let confirmed = try Data(contentsOf: target) == output
                            let residue = FileManager.default.fileExists(atPath: temporary.path)
                            report.measurements.append(
                                .init(name: "atomic-ms", value: elapsed, unit: "ms", tags: tags))
                            report.measurements.append(
                                .init(
                                    name: "atomic-confirmed", value: confirmed ? 1 : 0,
                                    unit: "bool", tags: tags))
                            report.measurements.append(
                                .init(
                                    name: "temporary-remains", value: residue ? 1 : 0, unit: "bool",
                                    tags: tags))
                        } catch {
                            let unchanged = (try? Data(contentsOf: target)) == original
                            report.measurements.append(
                                .init(name: "atomic-confirmed", value: 0, unit: "bool", tags: tags))
                            report.notes.append(
                                "Atomic \(tags): \(describe(error)); original unchanged=\(unchanged)"
                            )
                        }
                    }
                }
            }
            let residue = try FileManager.default.contentsOfDirectory(atPath: scratch.path).filter {
                $0.hasSuffix(".tmp")
            }
            report.measurements.append(
                .init(name: "temporary-residue-count", value: Double(residue.count), unit: "count"))
        } catch {
            report.notes.append("Suite stopped: \(describe(error))")
        }
        if owned {
            do {
                try FileManager.default.removeItem(at: scratch)
                report.notes.append("Removed owned clove-lab-s3 directory.")
            } catch { report.notes.append("Scratch cleanup failed: \(describe(error))") }
        }
        report.context["scratchRemains"] = String(
            FileManager.default.fileExists(atPath: scratch.path))
        report.notes.append(
            "Expected malformed input refusal is recorded per approach. No physical power-loss guarantee is established by read-back."
        )
        return report
    }

    public static func roundTrip(_ data: Data, fixture: String, approach: XMPApproach)
        -> [LabMeasurement]
    {
        var tags = ["fixture": fixture, "approach": approach.rawValue, "stage": "read"]
        let timer = Stopwatch()
        do {
            let initial = try approach.read(data)
            tags["initialRating"] = String(initial.rating)
            tags["initialLabel"] = initial.label
            tags["initialReject"] = String(initial.reject)
            tags["stage"] = "write"
            let output = try approach.write(data, marks: requested)
            tags["writeAccepted"] = "true"
            tags["stage"] = "read-back"
            let marks = try approach.read(output)
            tags["stage"] = "independent-inspection"
            let independent = try XMPInspection.inspect(output)
            let preserved = try XMPInspection.unknownDataPreserved(before: data, after: output)
            let representation = try XMPInspection.representationPreserved(
                before: data, after: output)
            return [
                .init(name: "roundtrip-ms", value: timer.seconds * 1000, unit: "ms", tags: tags),
                .init(
                    name: "marks-confirmed",
                    value: marks == requested && independent == requested ? 1 : 0, unit: "bool",
                    tags: tags),
                .init(
                    name: "unknown-data-preserved", value: preserved ? 1 : 0, unit: "bool",
                    tags: tags),
                .init(
                    name: "unknown-representation-preserved", value: representation ? 1 : 0,
                    unit: "bool", tags: tags),
                .init(name: "packet-bytes", value: Double(output.count), unit: "bytes", tags: tags),
            ]
        } catch {
            tags["error"] = describe(error)
            let name =
                tags["writeAccepted"] == "true" ? "roundtrip-invalid-output" : "roundtrip-refused"
            return [.init(name: name, value: 1, unit: "bool", tags: tags)]
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error) [\(nsError.domain):\(nsError.code)]"
    }
}

public enum XMPSidecarNaming {
    /// PRD rule 3: replace the primary extension; a paired JPG shares this URL.
    public static func sidecar(for primary: URL) -> URL {
        primary.deletingPathExtension().appendingPathExtension("xmp")
    }
}
