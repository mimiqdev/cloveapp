import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// The metadata adapter, tested against the exact property shapes the repository's fixtures
/// demonstrated (#208). Values come from the recorded fixture readings, so a regression in
/// the interpretation is caught without re-downloading the fixtures.
@Suite struct AutofocusMetadataReaderTests {
    let reader = AutofocusMetadataReader()

    /// `fujifilm-x-s10.RAF`: two identical corner+size tuples in `{ExifAux}.AFInfo`.
    @Test func readsFujiAFInfoCornerTuple() throws {
        let properties: [String: Any] = [
            "{TIFF}": ["Make": "FUJIFILM", "Orientation": 1],
            "{ExifAux}": [
                "AFInfo": [
                    0.265_172_1, 0.579_993_2, 0.049_818_84, 0.049_932_07, "f",
                    0.265_172_1, 0.579_993_2, 0.049_818_84, 0.049_932_07, "f",
                ]
            ],
        ]
        let region = try #require(try resultProperties(properties))
        // The stored corner (x, y) survives orientation 1 unchanged.
        #expect(abs(region.x - 0.265_172_1) < 1e-6)
        #expect(abs(region.y - 0.579_993_2) < 1e-6)
        #expect(abs(region.width - 0.049_818_84) < 1e-6)
    }

    /// `panasonic-dmc-gh4.RW2`: one corner+size tuple whose box centers at the frame's exact
    /// middle, which is what the corner reading predicts for the center AF point.
    @Test func readsPanasonicAFInfoAsCornerTuple() throws {
        let properties: [String: Any] = [
            "{TIFF}": ["Make": "Panasonic"],
            "{ExifAux}": ["AFInfo": [0.475, 0.475, 0.05, 0.05, "f"]],
        ]
        let region = try #require(try resultProperties(properties))
        // Corner semantics: (0.475, 0.475) + 0.05 centers at (0.5, 0.5).
        #expect(abs(region.centerX - 0.5) < 1e-6)
        #expect(abs(region.centerY - 0.5) < 1e-6)
    }

    /// `apple-iphone-12-pro.DNG`: a SubjectArea center+size rect in pixels, orientation 6.
    /// As a corner rect the values overflow the 4032×3024 frame; as a center rect they are
    /// dead-center, which orientation 6 must still display dead-center.
    @Test func readsAppleSubjectAreaAsCenterRect() throws {
        let properties: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Orientation": 6],
            "{Exif}": [
                "SubjectArea": [2009, 1506, 2318, 1390],
                "PixelXDimension": 4032,
                "PixelYDimension": 3024,
            ],
        ]
        let region = try #require(try resultProperties(properties))
        #expect(abs(region.centerX - 0.5) < 5e-3)
        #expect(abs(region.centerY - 0.5) < 5e-3)
        // Orientation 6 swaps the axes; the centered box stays inside the frame either way.
        #expect(region.x >= 0 && region.y >= 0)
        #expect(region.x + region.width <= 1 && region.y + region.height <= 1)
    }

    /// `sony-ilce-7s.ARW` and its HEIC: no path ImageIO exposes carries AF data, so the
    /// reader reports each inspected path missing, with the make recorded as evidence.
    @Test func sonyWithoutExposedCoordinatesReportsMissingWithEvidence() {
        let properties: [String: Any] = [
            "{TIFF}": ["Make": "SONY"],
            "{Exif}": ["PixelXDimension": 2768, "PixelYDimension": 1848],
            "{ExifAux}": ["FlashCompensation": 0],
        ]
        guard
            case .failure(let evidence) = reader.regions(
                of: URL(fileURLWithPath: "/"), properties: properties)
        else {
            Issue.record("Sony without exposed AF data must be unavailable")
            return
        }
        #expect(evidence.cameraMake == "SONY")
        #expect(
            evidence.inspected.map(\.path) == ["{ExifAux}.AFInfo", "{Exif}.SubjectArea"])
        #expect(evidence.inspected.allSatisfy { $0.finding == .missing })
    }

    /// A SubjectArea present but without pixel dimensions cannot be normalized, so the path
    /// is reported unreadable rather than guessed.
    @Test func subjectAreaWithoutPixelDimensionsIsUnreadable() {
        let properties: [String: Any] = [
            "{Exif}": ["SubjectArea": [100, 100, 50, 50]]
        ]
        guard
            case .failure(let evidence) = reader.regions(
                of: URL(fileURLWithPath: "/"), properties: properties)
        else {
            Issue.record("SubjectArea without dimensions must be unavailable")
            return
        }
        #expect(evidence.firstUnreadablePath == "{Exif}.SubjectArea")
    }

    /// AFInfo tuples that disagree are not evidence of one region, so they are rejected.
    @Test func disagreeingAFInfoTuplesAreRejected() {
        let properties: [String: Any] = [
            "{ExifAux}": [
                "AFInfo": [0.1, 0.1, 0.2, 0.2, "f", 0.8, 0.8, 0.1, 0.1, "f"]
            ]
        ]
        guard case .failure = reader.regions(of: URL(fileURLWithPath: "/"), properties: properties)
        else {
            Issue.record("Disagreeing AFInfo tuples must be unavailable")
            return
        }
    }

    /// AFInfo with values outside the frame is rejected rather than clamped into a guess.
    @Test func outOfFrameAFInfoIsRejected() {
        let properties: [String: Any] = [
            "{ExifAux}": ["AFInfo": [0.9, 0.9, 0.5, 0.5, "f"]]
        ]
        guard case .failure = reader.regions(of: URL(fileURLWithPath: "/"), properties: properties)
        else {
            Issue.record("Out-of-frame AFInfo must be unavailable")
            return
        }
    }

    /// AFInfo shapes the fixtures did not demonstrate are reported unreadable, never
    /// reinterpreted. A bare 4-tuple without the trailing flag is also unproven: both fixture
    /// cameras write the flag, so its absence is a different writer's shape.
    @Test func unprovenAFInfoShapesAreUnreadable() {
        let shapes: [[Any]] = [
            [0.5, 0.5],
            ["x", "y", "w", "h", "f"],
            [0.1, 0.1, 0.2, 0.2],
            [0.1, 0.1, 0.2, 0.2, "t", 0.1, 0.1, 0.2, 0.2],
        ]
        for shape in shapes {
            guard
                case .failure(let evidence) = reader.regions(
                    of: URL(fileURLWithPath: "/"),
                    properties: ["{ExifAux}": ["AFInfo": shape]])
            else {
                Issue.record("Unproven AFInfo shape \(shape) must be unavailable")
                continue
            }
            #expect(evidence.firstUnreadablePath == "{ExifAux}.AFInfo")
        }
    }

    private func resultProperties(_ properties: [String: Any]) throws -> NormalizedRegion {
        switch reader.regions(of: URL(fileURLWithPath: "/"), properties: properties) {
        case .success(let region): return region.region
        case .failure(let evidence):
            Issue.record("Expected a region, got \(evidence)")
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
