import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CloveImaging

/// Fixture-backed checks of the real metadata the adapter claims to support, plus the real\n/// Vision detector over a generated preview. The whole suite skips explicitly when the\n/// standard `formats` set is absent, so a missing fixture never reads as a pass (#208).
@Suite(.serialized, .enabled(if: SharpnessFixtures.hasFormats))
struct SharpnessFixtureTests {
    let reader = AutofocusMetadataReader()

    private func properties(of name: String) throws -> [String: Any] {
        let url = SharpnessFixtures.file(name)
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return properties
    }

    /// The Fuji fixture's AFInfo is a corner+size tuple repeated twice; both entries agree.
    @Test func fujiFixtureAFInfoProducesTheRecordedRegion() throws {
        let properties = try properties(of: "fujifilm-x-s10.RAF")
        guard
            case .success(let located) = reader.regions(
                of: SharpnessFixtures.file("fujifilm-x-s10.RAF"), properties: properties)
        else {
            Issue.record("The Fuji fixture's AFInfo is the proven shape")
            return
        }
        let region = located.region
        #expect(abs(region.x - 0.265_172_1) < 1e-6)
        #expect(abs(region.y - 0.579_993_2) < 1e-6)
        #expect(abs(region.width - 0.049_818_84) < 1e-6)
        #expect(abs(region.height - 0.049_932_07) < 1e-6)
    }

    /// The Panasonic fixture's single tuple centers its box at the frame's exact middle.
    @Test func panasonicFixtureAFInfoCentersAtTheFrameMiddle() throws {
        let properties = try properties(of: "panasonic-dmc-gh4.RW2")
        guard
            case .success(let located) = reader.regions(
                of: SharpnessFixtures.file("panasonic-dmc-gh4.RW2"), properties: properties)
        else {
            Issue.record("The Panasonic fixture's AFInfo is the proven shape")
            return
        }
        #expect(abs(located.region.centerX - 0.5) < 1e-6)
        #expect(abs(located.region.centerY - 0.5) < 1e-6)
    }

    /// The Apple fixture's SubjectArea is a center rect whose center sits within 0.2% of the
    /// frame's center; orientation 6 must display it there as well.
    @Test func appleFixtureSubjectAreaStaysCenteredAfterOrientation() throws {
        let properties = try properties(of: "apple-iphone-12-pro.DNG")
        guard
            case .success(let located) = reader.regions(
                of: SharpnessFixtures.file("apple-iphone-12-pro.DNG"), properties: properties)
        else {
            Issue.record("The Apple fixture's SubjectArea is the proven shape")
            return
        }
        #expect(abs(located.region.centerX - 0.5) < 5e-3)
        #expect(abs(located.region.centerY - 0.5) < 5e-3)
    }

    /// The Sony fixtures expose no AF path through ImageIO; both must report unavailable with
    /// the inspected paths as evidence, not a guessed region (#208).
    @Test func sonyFixturesReportUnavailableWithEvidence() throws {
        for name in ["sony-ilce-7s.ARW", "sony-ilce-7s.HEIC"] {
            let properties = try properties(of: name)
            guard
                case .failure(let evidence) = reader.regions(
                    of: SharpnessFixtures.file(name), properties: properties)
            else {
                Issue.record("\(name) has no ImageIO-exposed AF data and must be unavailable")
                continue
            }
            #expect(evidence.cameraMake == "SONY", Comment(rawValue: name))
            #expect(
                evidence.inspected.map(\.path) == ["{ExifAux}.AFInfo", "{Exif}.SubjectArea"],
                Comment(rawValue: name))
            #expect(
                evidence.inspected.allSatisfy { $0.finding == .missing }, Comment(rawValue: name))
        }
    }

    /// Every other fixture file must also answer deterministically: either a supported shape
    /// or explicit evidence. This catches a new fixture silently changing the adapter's world.
    @Test func everyFormatsFixtureAnswersDeterministically() throws {
        let files = try FileManager.default.contentsOfDirectory(
            atPath: SharpnessFixtures.formats.path)
        for name in files.sorted() {
            let properties = try properties(of: name)
            switch reader.regions(of: SharpnessFixtures.file(name), properties: properties) {
            case .success:
                // A located region is always inside the displayed frame.
                let region = try #require(
                    try locatedRegion(name, properties: properties)?.region, Comment(rawValue: name)
                )
                #expect(region.x >= 0 && region.y >= 0, Comment(rawValue: name))
                #expect(region.x + region.width <= 1.0001, Comment(rawValue: name))
                #expect(region.y + region.height <= 1.0001, Comment(rawValue: name))
            case .failure(let evidence):
                #expect(!evidence.inspected.isEmpty, Comment(rawValue: name))
            }
        }
    }

    private func locatedRegion(_ name: String, properties: [String: Any]) throws -> AutofocusRegion?
    {
        if case .success(let located) = reader.regions(
            of: SharpnessFixtures.file(name), properties: properties)
        {
            return located
        }
        return nil
    }

    /// The real Vision detector over a face-like generated preview. It does not assert a
    /// detection — Vision's behaviour on synthetic scenes is the platform's, not Clove's —
    /// but it proves the request runs and answers through the seam on this host.
    @Test func visionDetectorRunsOnAGeneratedPreview() async throws {
        let detector = VisionFaceRegionDetector()
        let preview = SharpnessScene.checkerboard(width: 800, height: 600, cell: 8)
        let outcome = await detector.detectFaces(on: preview)
        switch outcome {
        case .faces(let faces):
            // No assertion on the count: the check is that the request ran and reported.
            print("SHARPNESS vision preview-faces=\(faces.count) (informational)")
        case .failed(let message):
            // Vision can be unavailable on a host; the analysis reports it, never crashes.
            print("SHARPNESS vision preview-failed=\(message) (informational)")
        }
    }
}

/// The shared fixture cache, resolved the way the other suites resolve it.
enum SharpnessFixtures {
    static let root = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
            ?? "/Volumes/T7/Projects/.clove-fixtures")

    static var formats: URL { root.appendingPathComponent("sets/formats") }
    static var hasFormats: Bool { FileManager.default.fileExists(atPath: formats.path) }
    static func file(_ name: String) -> URL { formats.appendingPathComponent(name) }
}
