import Foundation
import Testing

@testable import CloveImaging

private struct MetadataFixture: Sendable {
    let name: String
    let subseconds: String?
    let serialPath: String?
}

private let metadataFixtures: [MetadataFixture] = [
    .init(name: "apple-iphone-12-pro.DNG", subseconds: "700", serialPath: nil),
    .init(name: "canon-eos-6d.JPG", subseconds: "00", serialPath: "{Exif}.BodySerialNumber"),
    .init(name: "canon-eos-r6.CR3", subseconds: "06", serialPath: "{Exif}.BodySerialNumber"),
    .init(name: "fujifilm-x-s10.RAF", subseconds: nil, serialPath: "{Exif}.BodySerialNumber"),
    .init(name: "nikon-d500.NEF", subseconds: "89", serialPath: "{ExifAux}.SerialNumber"),
    .init(name: "olympus-e-m1markii.ORF", subseconds: nil, serialPath: "{ExifAux}.SerialNumber"),
    .init(name: "panasonic-dmc-gh4.RW2", subseconds: "842", serialPath: "{ExifAux}.SerialNumber"),
    .init(name: "pentax-k-5-ii-s.DNG", subseconds: nil, serialPath: "{ExifAux}.SerialNumber"),
    .init(name: "sony-ilce-7s.ARW", subseconds: nil, serialPath: nil),
    .init(name: "sony-ilce-7s.HEIC", subseconds: nil, serialPath: nil),
]

private func fixtureFolder() -> URL {
    let root =
        ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
        ?? "/Volumes/T7/Projects/.clove-fixtures"
    return URL(fileURLWithPath: root).appendingPathComponent("sets/formats")
}

@Test func metadataMatchesDocumentedFixtureAvailability() throws {
    let reader = MetadataReader()
    for fixture in metadataFixtures {
        let url = fixtureFolder().appendingPathComponent(fixture.name)
        // This is the issue's acceptance coverage: absent fixtures must not silently skip it.
        #expect(FileManager.default.fileExists(atPath: url.path), "Run mise run fixtures-sets")
        guard case .success(let metadata) = reader.read(url: url).outcome else {
            Issue.record("Cannot read metadata for \(fixture.name)")
            continue
        }
        let capture = try #require(metadata.captureTime.value, "\(fixture.name)")
        #expect(metadata.captureTime.source == .imageProperty("{Exif}.DateTimeOriginal"))
        #expect(metadata.time == .captureMetadata(capture))
        #expect(metadata.model.value?.isEmpty == false)
        #expect(metadata.model.source == .imageProperty("{TIFF}.Model"))
        #expect(metadata.subseconds.value == fixture.subseconds, "\(fixture.name)")
        #expect(metadata.utcOffset == .missing)
        #expect(capture.timestamp == .cameraWallTime(capture.wallTime))
        if let path = fixture.serialPath {
            #expect(metadata.bodySerial.value?.isEmpty == false, "\(fixture.name)")
            #expect(metadata.bodySerial.source == .imageProperty(path))
        } else {
            #expect(metadata.bodySerial == .missing, "\(fixture.name)")
        }
    }
}

@Test func metadataReadTimingIsInformational() throws {
    let reader = MetadataReader(maximumConcurrentReads: 1)
    var times: [Double] = []
    // Three serial passes, 30 reads total. No cache flush, no performance assertion.
    for _ in 0..<3 {
        for fixture in metadataFixtures {
            let start = ContinuousClock.now
            let result = reader.read(url: fixtureFolder().appendingPathComponent(fixture.name))
            let duration = start.duration(to: .now).components
            guard case .success = result.outcome else {
                Issue.record("Timing input unavailable: \(fixture.name)")
                continue
            }
            times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
    }
    let sorted = times.sorted()
    #expect(sorted.count == 30)
    guard sorted.count == 30 else { return }
    let median = (sorted[14] + sorted[15]) / 2
    print(
        String(
            format:
                "Metadata read: macOS serial per-file median %.3f ms (30 reads, 10 fixtures, 3 passes; informational)",
            median))
}
