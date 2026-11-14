import Foundation
import Synchronization
import Testing

import CameraFocusMetadata
@testable import CloveImaging

/// The focusmeta bridge (#238): a stub file reader answers for focusmeta, so every test
/// states the exact conclusion the bridge must map. The conclusions themselves come from
/// real focusmeta reads of the synthetic containers, so the values the bridge maps are the
/// library's own products, not hand-built lookalikes. Whole-container behaviour lives in
/// ``RealSonyBridgeTests``.
@Suite(.imageWork) struct FocusMetaBridgeTests {
    /// Reads a synthetic Sony ARW with focusmeta and reduces it to the bridge's conclusion.
    /// Only `vendor` and `status` can be stated directly; every geometry value is the
    /// library's own output for the given record.
    private static func readConclusion(
        vendor: CameraVendor? = .sony,
        model: String? = "ILCE-1M2",
        status: ExtractionStatus = .verifiedSonyFocusMetadata,
        orientation: UInt16 = 1,
        location: (UInt16, UInt16, UInt16, UInt16)? = (80, 60, 17, 31),
        frame: (UInt16, UInt16, UInt16)? = (10, 6, 257)
    ) throws -> AutofocusMetadataReader.FocusMetadataConclusion {
        let data = SyntheticSonyContainer.arw(
            model: model, orientation: orientation, location: location, frame: frame)
        let report = try #require(
            try FocusMetadataReader().read(data: data), "The synthetic container parses")
        let read = AutofocusMetadataReader.conclusion(of: report)
        return AutofocusMetadataReader.FocusMetadataConclusion(
            vendor: vendor ?? read.vendor, model: model, recordedMake: read.recordedMake,
            focus: read.focus, displayGeometry: read.displayGeometry, status: status)
    }

    /// ImageIO's view of a Sony file: every AF path missing, so the fallback runs.
    private static func sonyProperties() -> [String: Any] {
        [
            "{TIFF}": ["Make": "SONY"],
            "{Exif}": ["PixelXDimension": 80, "PixelYDimension": 60],
        ]
    }

    // MARK: - Mapping

    private static func reader(conclusion: AutofocusMetadataReader.FocusMetadataConclusion?)
        throws -> AutofocusMetadataReader
    {
        struct StubFiles: AutofocusMetadataReader.MetadataFileReading {
            let conclusion: AutofocusMetadataReader.FocusMetadataConclusion?
            func readMetadataFile(at url: URL) -> AutofocusMetadataReader.FocusMetadataConclusion? {
                conclusion
            }
        }
        return AutofocusMetadataReader(metadataFiles: StubFiles(conclusion: conclusion))
    }

    /// A display-space region keeps its center and size, normalized against the display
    /// extent the library already rotated: the stored orientation is not applied again.
    /// The synthetic record uses a stored extent of 80×60 with orientation 6, so the display
    /// extent is 60×80 and the stored center (17, 31) lands at (60 − 31, 17) in display
    /// pixels.
    @Test func mapsDisplayRegionIntoNormalizedRegion() throws {
        let located = try #require(
            try Self.locate(
                reader: Self.reader(
                    conclusion: try Self.readConclusion(orientation: 6)),
                properties: Self.sonyProperties()))
        // Display extent 60×80: focusmeta's center, against the display extent — not the
        // stored 80×60.
        #expect(abs(located.centerX - (60.0 - 31.0) / 60.0) < 1e-9)
        #expect(abs(located.centerY - 17.0 / 80.0) < 1e-9)
        // The frame (10, 6) swaps axes under the quarter turn.
        #expect(abs(located.width - 6.0 / 60.0) < 1e-9)
        #expect(abs(located.height - 10.0 / 80.0) < 1e-9)
    }

    /// A located point without a recorded extent still locates: the small presented box
    /// centers on the recorded point, and the scorer decides whether it is too small to score.
    @Test func mapsLocatedPointIntoThePresentedBox() throws {
        let located = try #require(
            try Self.locate(
                reader: Self.reader(
                    conclusion: try Self.readConclusion(frame: nil)),
                properties: Self.sonyProperties()))
        // Orientation 1: the stored center is the display center.
        #expect(abs(located.centerX - 17.0 / 80.0) < 1e-9)
        #expect(abs(located.centerY - 31.0 / 60.0) < 1e-9)
        #expect(abs(located.width - AutofocusMetadataReader.locatedRegionSize) < 1e-9)
        #expect(abs(located.height - AutofocusMetadataReader.locatedRegionSize) < 1e-9)
    }

    /// An out-of-frame geometry is not evidence Clove can locate: focusmeta declines the
    /// record itself, so the mapping never sees it — asserted through the synthetic
    /// out-of-range record (center 65535 in an 80×60 reference).
    @Test func outOfFrameGeometryIsDeclined() throws {
        let conclusion = try #require(
            try Self.readConclusion(location: (80, 60, 65535, 65535)).displayGeometry == nil
                ? Self.readConclusion(location: (80, 60, 65535, 65535))
                : nil,
            "focusmeta must not derive geometry for an out-of-range record")
        guard
            case .failure(let evidence) = try Self.reader(conclusion: conclusion).regions(
                of: URL(fileURLWithPath: "/"), properties: Self.sonyProperties())
        else {
            Issue.record("An out-of-frame record must be unavailable")
            return
        }
        #expect(
            evidence.inspected.contains { $0.path.hasPrefix("focusmeta.SonyMakerNote") })
    }

    /// The proven ImageIO shapes never consult focusmeta, so the Fuji, Panasonic and Apple
    /// readings keep their route and their values unchanged.
    @Test func provenImageIOPathsBypassFocusmeta() throws {
        final class CountingFiles: AutofocusMetadataReader.MetadataFileReading {
            let reads = Mutex(0)
            func readMetadataFile(at url: URL) -> AutofocusMetadataReader.FocusMetadataConclusion? {
                reads.withLock { $0 += 1 }
                return nil
            }
        }
        let files = CountingFiles()
        let reader = AutofocusMetadataReader(metadataFiles: files)

        let fuji: [String: Any] = [
            "{TIFF}": ["Make": "FUJIFILM"],
            "{ExifAux}": [
                "AFInfo": [0.2, 0.2, 0.1, 0.1, "f", 0.2, 0.2, 0.1, 0.1, "f"]
            ],
        ]
        let panasonic: [String: Any] = [
            "{TIFF}": ["Make": "Panasonic"],
            "{ExifAux}": ["AFInfo": [0.475, 0.475, 0.05, 0.05, "f"]],
        ]
        let apple: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Orientation": 6],
            "{Exif}": [
                "SubjectArea": [1000, 2200, 400, 300],
                "PixelXDimension": 4000,
                "PixelYDimension": 3000,
            ],
        ]

        for (name, properties) in [("fuji", fuji), ("panasonic", panasonic), ("apple", apple)] {
            guard
                case .success(let region) = reader.regions(
                    of: URL(fileURLWithPath: "/"), properties: properties)
            else {
                Issue.record("\(name) must keep its proven ImageIO reading")
                continue
            }
            #expect(region.region.width > 0, Comment(rawValue: name))
        }
        #expect(files.reads.withLock { $0 } == 0, "focusmeta runs only when ImageIO found nothing")
    }

    // MARK: - Unavailable with evidence

    /// A Sony file focusmeta parsed but could not present geometry for: the reader reports
    /// unavailable with focusmeta's own conclusion as evidence — never a guess, never silence.
    @Test func sonyGeometryUnavailableCarriesFocusmetaEvidence() throws {
        let cases: [(String, AutofocusMetadataReader.FocusMetadataConclusion)] = [
            (
                "no focus record",
                try Self.readConclusion(
                    status: .focusMetadataMissing, location: nil, frame: nil)
            ),
            (
                "frame not presented",
                try Self.readConclusion(frame: (10, 6, 0))
            ),
            (
                "out-of-range record",
                try Self.readConclusion(location: (80, 60, 65535, 65535))
            ),
        ]
        for (name, conclusion) in cases {
            guard
                case .failure(let evidence) = try Self.reader(conclusion: conclusion).regions(
                    of: URL(fileURLWithPath: "/"), properties: Self.sonyProperties())
            else {
                Issue.record("\(name) must be unavailable")
                continue
            }
            #expect(evidence.cameraMake == "SONY", Comment(rawValue: name))
            let paths = evidence.inspected.map(\.path)
            #expect(paths.contains("{ExifAux}.AFInfo"), Comment(rawValue: name))
            #expect(
                paths.contains { $0.hasPrefix("focusmeta.SonyMakerNote") },
                Comment(rawValue: name))
        }
    }

    /// Another vendor's raw observations map to explicit unavailability naming the vendor,
    /// not to silence and not to a centered guess. The conclusion comes from a real read of
    /// a synthetic Canon JPEG — a maker note focusmeta does not interpret — and the same
    /// reduction is asserted for every other non-Sony vendor focusmeta can name.
    @Test func otherVendorsStayExplicitlyUnavailable() throws {
        let jpeg = SyntheticSonyContainer.jpeg(
            make: "Canon", model: "Canon EOS R6",
            makerNote: [0x00, 0x0e, 0x00, 0x00, 0xaa, 0xbb])
        let report = try #require(
            try FocusMetadataReader().read(data: jpeg), "The synthetic JPEG parses")
        let read = AutofocusMetadataReader.conclusion(of: report)
        #expect(read.vendor == .canon)
        #expect(read.displayGeometry == nil)

        for vendor in [CameraVendor.canon, .nikon, .olympus, .pentax, .unknown] {
            let conclusion = AutofocusMetadataReader.FocusMetadataConclusion(
                vendor: vendor, model: read.model, recordedMake: read.recordedMake,
                focus: read.focus, displayGeometry: read.displayGeometry,
                status: read.status)
            guard
                case .failure(let evidence) = try Self.reader(conclusion: conclusion).regions(
                    of: URL(fileURLWithPath: "/"), properties: ["{TIFF}": ["Make": "Whatever"]])
            else {
                Issue.record("\(vendor.rawValue) must stay unavailable")
                continue
            }
            #expect(
                evidence.inspected.contains {
                    $0.path.hasPrefix("focusmeta.") && $0.finding != .missing
                },
                "\(vendor.rawValue) needs explicit evidence")
        }
    }

    /// A file focusmeta could not open or read at all keeps the ImageIO evidence: the
    /// fallback adds nothing it cannot support.
    @Test func unreadableMetadataFileKeepsImageIOEvidence() throws {
        guard
            case .failure(let evidence) = try Self.reader(conclusion: nil).regions(
                of: URL(fileURLWithPath: "/"), properties: Self.sonyProperties())
        else {
            Issue.record("No conclusion means unavailable")
            return
        }
        #expect(evidence.cameraMake == "SONY")
        #expect(
            evidence.inspected.map(\.path) == ["{ExifAux}.AFInfo", "{Exif}.SubjectArea"])
    }

    // MARK: - Orientation agreement

    /// focusmeta's display geometry and Clove's own orientation map must agree on axis
    /// semantics for every EXIF orientation 1–8: the library's display center equals what
    /// Clove's `oriented(forExifOrientation:)` computes from the same stored center. A
    /// disagreement means mirrored or rotated overlays, so it is pinned by construction here
    /// and against real containers in ``RealSonyBridgeTests``.
    @Test func displayGeometryAgreesWithClovesOrientationMapAcrossAllEightOrientations() throws {
        // A stored extent of 4000×3000 with an off-center stored region: center (1000, 2200),
        // size (400, 300). Every orientation moves it differently, so agreement is not
        // vacuous for the centered case.
        let storedExtent = try #require(PixelExtent(width: 4000, height: 3000))
        let storedCenter = ContinuousPoint(x: 1000, y: 2200)
        let storedSize = ContinuousSize(width: 400, height: 300)

        for rawOrientation in UInt16(1)...UInt16(8) {
            let orientation = try #require(
                ExifOrientation(rawValue: rawOrientation),
                "Orientation \(rawOrientation) is one of the eight standard values")
            // focusmeta's normalized display center and size, from a real read of a
            // synthetic ARW carrying this orientation…
            let data = SyntheticSonyContainer.arw(
                orientation: rawOrientation,
                location: (4000, 3000, 1000, 2200), frame: (400, 300, 257))
            let report = try #require(
                try FocusMetadataReader().read(data: data),
                "The synthetic container parses")
            let display = try #require(
                report.displayGeometry, "orientation \(rawOrientation) derives display geometry")
            guard case .region(let displayRegion) = display else {
                Issue.record("orientation \(rawOrientation) is a region")
                continue
            }
            // …against Clove's map of the same stored values.
            let storedRegion = NormalizedRegion(
                x: (storedCenter.x - storedSize.width / 2) / Double(storedExtent.width),
                y: (storedCenter.y - storedSize.height / 2) / Double(storedExtent.height),
                width: storedSize.width / Double(storedExtent.width),
                height: storedSize.height / Double(storedExtent.height))
            let cloveRegion = storedRegion.oriented(forExifOrientation: Int(rawOrientation))

            #expect(
                abs(displayRegion.normalizedCenter.x - cloveRegion.centerX) < 1e-9,
                "orientation \(rawOrientation) x")
            #expect(
                abs(displayRegion.normalizedCenter.y - cloveRegion.centerY) < 1e-9,
                "orientation \(rawOrientation) y")
            #expect(
                abs(displayRegion.normalizedSize.width - cloveRegion.width) < 1e-9,
                "orientation \(rawOrientation) width")
            #expect(
                abs(displayRegion.normalizedSize.height - cloveRegion.height) < 1e-9,
                "orientation \(rawOrientation) height")
        }
    }

    private static func locate(
        reader: AutofocusMetadataReader, properties: [String: Any]
    ) throws -> NormalizedRegion? {
        switch try reader.regions(of: URL(fileURLWithPath: "/"), properties: properties) {
        case .success(let located): return located.region
        case .failure(let evidence):
            Issue.record("Expected a located region, got \(evidence)")
            return nil
        }
    }
}
