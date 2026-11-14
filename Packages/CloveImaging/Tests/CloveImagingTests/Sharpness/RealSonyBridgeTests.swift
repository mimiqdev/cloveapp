import Foundation
import Testing

import CameraFocusMetadata
@testable import CloveImaging

/// The bridge over real focusmeta reads of synthetic containers (#238): the synthetic ARW and
/// HIF bytes are parsed by the vendored library exactly as the private ILCE-1M2 samples are,
/// which proves the whole route — file read, Sony maker-note parse, display rotation, mapping
/// — without the private files ever entering the repository.
@Suite(.imageWork) struct RealSonyBridgeTests {
    /// A reader over a temporary file: focusmeta reads from disk the way production does.
    private static func reader(writing data: Data) throws -> (AutofocusMetadataReader, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clove-focusmeta-\(UUID().uuidString).bin")
        try data.write(to: url)
        return (AutofocusMetadataReader(), url)
    }

    /// ImageIO's view of a Sony file: every AF path missing. The synthetic containers are not
    /// decodable images, so the property dictionary is stated the way the real fixtures read.
    private static func sonyImageIOProperties() -> [String: Any] {
        [
            "{TIFF}": ["Make": "SONY"],
            "{Exif}": ["PixelXDimension": 80, "PixelYDimension": 60],
        ]
    }

    /// An ARW with orientation 1: the stored location is the display location, and the
    /// recorded frame size becomes the region size.
    @Test func syntheticARWOrientation1LocatesTheRecordedRegion() throws {
        let (reader, url) = try Self.reader(
            writing: SyntheticSonyContainer.arw(orientation: 1))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            case .success(let located) = reader.regions(
                of: url, properties: Self.sonyImageIOProperties())
        else {
            Issue.record("A verified Sony record must locate")
            return
        }
        // Stored and display space agree at orientation 1: center 17/80, 31/60.
        #expect(abs(located.region.centerX - 17.0 / 80.0) < 1e-9)
        #expect(abs(located.region.centerY - 31.0 / 60.0) < 1e-9)
        #expect(abs(located.region.width - 10.0 / 80.0) < 1e-9)
        #expect(abs(located.region.height - 6.0 / 60.0) < 1e-9)
    }

    /// An ARW with orientation 6: the stored location is rotated into display space by
    /// focusmeta, and the result equals Clove's own orientation map applied to the stored
    /// region — the axis-semantics agreement this integration exists to prove.
    @Test func syntheticARWOrientation6AgreesWithClovesOrientationMap() throws {
        let (reader, url) = try Self.reader(
            writing: SyntheticSonyContainer.arw(orientation: 6))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            let located = try locatedRegion(
                reader, url: url, properties: Self.sonyImageIOProperties())
        else { return }
        // Clove's map of the same stored region: center (17/80, 31/60), size (10/80, 6/60),
        // orientation 6. The axes swap, so the display size is (6/60, 10/80).
        let stored = NormalizedRegion(
            x: 17.0 / 80.0 - (10.0 / 80.0) / 2, y: 31.0 / 60.0 - (6.0 / 60.0) / 2,
            width: 10.0 / 80.0, height: 6.0 / 60.0)
        let expected = stored.oriented(forExifOrientation: 6)
        #expect(abs(located.centerX - expected.centerX) < 1e-9)
        #expect(abs(located.centerY - expected.centerY) < 1e-9)
        #expect(abs(located.width - expected.width) < 1e-9)
        #expect(abs(located.height - expected.height) < 1e-9)
        // The swapped axes are visible in the located size itself.
        #expect(abs(located.width - 6.0 / 60.0) < 1e-9)
        #expect(abs(located.height - 10.0 / 80.0) < 1e-9)
    }

    /// The mirrored orientations: 2 mirrors horizontally, 4 vertically, 3 rotates 180°, and
    /// 5, 7, 8 transpose. Each display region must equal Clove's map of the same stored
    /// values, pinning the axis semantics for the whole eight-value family.
    @Test func syntheticARWEveryOrientationAgreesWithClovesOrientationMap() throws {
        for orientation in UInt16(1)...UInt16(8) {
            let (reader, url) = try Self.reader(
                writing: SyntheticSonyContainer.arw(orientation: orientation))
            defer { try? FileManager.default.removeItem(at: url) }

            guard
                let located = try locatedRegion(
                    reader, url: url, properties: Self.sonyImageIOProperties())
            else {
                Issue.record("orientation \(orientation) must locate")
                continue
            }
            let expected = NormalizedRegion(
                x: 17.0 / 80.0 - (10.0 / 80.0) / 2, y: 31.0 / 60.0 - (6.0 / 60.0) / 2,
                width: 10.0 / 80.0, height: 6.0 / 60.0
            ).oriented(forExifOrientation: Int(orientation))
            #expect(abs(located.centerX - expected.centerX) < 1e-9, "orientation \(orientation) x")
            #expect(abs(located.centerY - expected.centerY) < 1e-9, "orientation \(orientation) y")
            #expect(abs(located.width - expected.width) < 1e-9, "orientation \(orientation) width")
            #expect(
                abs(located.height - expected.height) < 1e-9, "orientation \(orientation) height")
        }
    }

    /// An HIF whose primary image carries `irot` 1: HEIF's quarter turns are
    /// counter-clockwise, so payload 1 is a 270° clockwise display rotation, and the Exif
    /// item embeds the same stored Sony record. The display region must match the equivalent
    /// EXIF orientation map (irot 1 ≡ EXIF 8).
    @Test func syntheticHIFRotationAgreesWithTheEquivalentExifMap() throws {
        let (reader, url) = try Self.reader(writing: SyntheticSonyContainer.heif(irot: 1))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            let located = try locatedRegion(
                reader, url: url, properties: Self.sonyImageIOProperties())
        else { return }
        let expected = NormalizedRegion(
            x: 17.0 / 80.0 - (10.0 / 80.0) / 2, y: 31.0 / 60.0 - (6.0 / 60.0) / 2,
            width: 10.0 / 80.0, height: 6.0 / 60.0
        ).oriented(forExifOrientation: 8)
        #expect(abs(located.centerX - expected.centerX) < 1e-9)
        #expect(abs(located.centerY - expected.centerY) < 1e-9)
        #expect(abs(located.width - expected.width) < 1e-9)
        #expect(abs(located.height - expected.height) < 1e-9)
    }

    /// A location record with no frame size — focusmeta's location-only geometry — still
    /// locates the recorded point with the presented box.
    @Test func syntheticARWWithoutFrameLocatesThePoint() throws {
        let (reader, url) = try Self.reader(
            writing: SyntheticSonyContainer.arw(frame: nil))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            let located = try locatedRegion(
                reader, url: url, properties: Self.sonyImageIOProperties())
        else { return }
        #expect(abs(located.centerX - 17.0 / 80.0) < 1e-9)
        #expect(abs(located.centerY - 31.0 / 60.0) < 1e-9)
        #expect(abs(located.width - AutofocusMetadataReader.locatedRegionSize) < 1e-9)
    }

    /// A Sony MakerNote with no focus record at all is unavailable with evidence that names
    /// the Sony read, not a centered guess.
    @Test func syntheticARWWithoutFocusRecordIsUnavailableWithEvidence() throws {
        let data = SyntheticSonyContainer.arw(
            location: nil, frame: nil)
        let (reader, url) = try Self.reader(writing: data)
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            case .failure(let evidence) = reader.regions(
                of: url, properties: Self.sonyImageIOProperties())
        else {
            Issue.record("No focus record means unavailable")
            return
        }
        #expect(evidence.cameraMake == "SONY")
        #expect(
            evidence.inspected.contains { $0.path.hasPrefix("focusmeta.SonyMakerNote") })
        #expect(evidence.inspected.contains { $0.finding != .missing })
    }

    /// An availability word focusmeta's reference tools never displayed (0) produces no
    /// region, and the evidence carries the reason.
    @Test func syntheticARWWithUnpresentedFrameIsUnavailable() throws {
        let (reader, url) = try Self.reader(
            writing: SyntheticSonyContainer.arw(frame: (10, 6, 0)))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            case .failure(let evidence) = reader.regions(
                of: url, properties: Self.sonyImageIOProperties())
        else {
            Issue.record("An unpresented frame must not locate")
            return
        }
        #expect(
            evidence.inspected.contains { $0.path.hasPrefix("focusmeta.SonyMakerNote") })
    }

    /// A container focusmeta does not recognize keeps the ImageIO evidence unchanged: the
    /// fallback adds nothing for a file outside its scope.
    @Test func unrecognizedContainerKeepsImageIOEvidence() throws {
        let (reader, url) = try Self.reader(writing: Data([0x00, 0x01, 0x02, 0x03]))
        defer { try? FileManager.default.removeItem(at: url) }

        guard
            case .failure(let evidence) = reader.regions(
                of: url, properties: Self.sonyImageIOProperties())
        else {
            Issue.record("An unrecognized container must be unavailable")
            return
        }
        #expect(
            evidence.inspected.map(\.path) == ["{ExifAux}.AFInfo", "{Exif}.SubjectArea"])
    }

    private func locatedRegion(
        _ reader: AutofocusMetadataReader, url: URL, properties: [String: Any]
    ) throws -> NormalizedRegion? {
        switch reader.regions(of: url, properties: properties) {
        case .success(let located): return located.region
        case .failure(let evidence):
            Issue.record("Expected a located region, got \(evidence)")
            return nil
        }
    }
}
