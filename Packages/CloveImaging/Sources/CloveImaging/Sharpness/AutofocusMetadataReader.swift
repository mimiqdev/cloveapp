import CoreGraphics
import Foundation
import ImageIO
import CameraFocusMetadata

/// The property paths one file was inspected for, and what was found, so an unavailable answer
/// can show its evidence instead of an unexplained empty result (#208).
public struct AutofocusMetadataEvidence: Error, Codable, Sendable, Equatable {
    public enum Finding: Codable, Sendable, Equatable {
        /// The path was not present in the file's properties.
        case missing
        /// The path was present but its shape was not understood; the raw description is kept.
        case unreadable(String)
    }

    /// One inspected property path and what was found in it.
    public struct Inspection: Codable, Sendable, Equatable {
        public let path: String
        public let finding: Finding

        public init(path: String, finding: Finding) {
            self.path = path
            self.finding = finding
        }
    }

    /// Each metadata path inspected, in the order the reader prefers them, with its finding.
    public let inspected: [Inspection]
    /// The file's `{TIFF}.Make`, when present, naming whose AF record this is.
    public let cameraMake: String?
    /// The EXIF orientation the file records, which a located region must be mapped through.
    public let exifOrientation: Int

    public init(inspected: [Inspection], cameraMake: String?, exifOrientation: Int) {
        self.inspected = inspected
        self.cameraMake = cameraMake
        self.exifOrientation = exifOrientation
    }

    /// The first inspected path that was present but unreadable, for a short report.
    public var firstUnreadablePath: String? {
        inspected.first { if case .unreadable = $0.finding { return true } else { return false } }?
            .path
    }
}

/// One camera-AF region located from a file's metadata, in the displayed-image space.
public struct AutofocusRegion: Sendable {
    public let region: NormalizedRegion
    public init(region: NormalizedRegion) {
        self.region = region
    }
}

/// Reads camera autofocus regions from ImageIO's property dictionaries, falling back to
/// the vendored focusmeta reader for the cameras whose AF records ImageIO never exposes
/// (Sony today: private maker notes). Proven paths stay on ImageIO unchanged; see
/// ``regionsFromMetadataFile(of:)`` for when the fallback runs.
///
/// Only coordinate shapes proven against the repository's fixtures are interpreted; anything
/// else reports unavailable with the evidence of what was inspected (#208):
///
/// - `{ExifAux}.AFInfo` — a `[x, y, width, height, flag]` array of normalized values, proven on
///   `fujifilm-x-s10.RAF` and `panasonic-dmc-gh4.RW2` (corner + size, both entries identical).
/// - `{Exif}.SubjectArea` — a `[x, y, width, height]` array of pixels relative to the file's
///   pixel dimensions, proven on `apple-iphone-12-pro.DNG` (center + size; the fixture's values
///   overflow as a corner rect and are exact as a center rect).
///
/// Sony cameras record AF data in private maker-note blocks that ImageIO does not expose — this
/// host's SDK has no Sony dictionary at all — so after both paths above report missing, the
/// reader re-reads the file with focusmeta, which parses the Sony blocks directly and maps its
/// display-space geometry into the same ``NormalizedRegion`` the proven paths produce.
public struct AutofocusMetadataReader: Sendable {
    /// Reads whole metadata containers (Sony maker notes live outside ImageIO's property
    /// dictionaries). Production reads the file; tests read synthetic bytes or state
    /// conclusions.
    public protocol MetadataFileReading: Sendable {
        func readMetadataFile(at url: URL) -> FocusMetadataConclusion?
    }

    /// focusmeta over the real file: bounded reads, no image decoding, no caching. A
    /// conclusion is returned even for unsupported and malformed files; only a failed
    /// open/read is nil.
    private struct FocusMetadataFileReader: MetadataFileReading {
        func readMetadataFile(at url: URL) -> FocusMetadataConclusion? {
            (try? FocusMetadataReader().read(fileAt: url)).map(
                AutofocusMetadataReader.conclusion(of:))
        }
    }

    private let metadataFiles: any MetadataFileReading

    public init() {
        self.init(metadataFiles: FocusMetadataFileReader())
    }

    init(metadataFiles: any MetadataFileReading) {
        self.metadataFiles = metadataFiles
    }

    public func regions(
        of url: URL, properties: [String: Any]
    ) -> Result<AutofocusRegion, AutofocusMetadataEvidence> {
        let tiff = properties["{TIFF}"] as? [String: Any] ?? [:]
        let make = tiff["Make"] as? String
        let exif = properties["{Exif}"] as? [String: Any] ?? [:]
        let aux = properties["{ExifAux}"] as? [String: Any] ?? [:]
        // The root orientation matches the pixels ImageIO delivers (DetailRenderer and
        // DetailNativeSize read it the same way); TIFF is the fallback a bare EXIF-only
        // dictionary offers.
        let orientation =
            properties["Orientation"] as? Int
            ?? tiff["Orientation"] as? Int ?? 1

        var inspected: [AutofocusMetadataEvidence.Inspection] = []
        if let afInfo = aux["AFInfo"] {
            inspected.append(
                .init(path: "{ExifAux}.AFInfo", finding: .unreadable(String(describing: afInfo))))
            if let region = Self.afInfoRegion(afInfo) {
                return .success(
                    AutofocusRegion(region: region.oriented(forExifOrientation: orientation)))
            }
        } else {
            inspected.append(.init(path: "{ExifAux}.AFInfo", finding: .missing))
        }

        if let subjectArea = exif["SubjectArea"] {
            inspected.append(
                .init(
                    path: "{Exif}.SubjectArea",
                    finding: .unreadable(String(describing: subjectArea))))
            let width = (exif["PixelXDimension"] as? Int) ?? 0
            let height = (exif["PixelYDimension"] as? Int) ?? 0
            if let region = Self.subjectAreaRegion(
                subjectArea, pixelWidth: width, pixelHeight: height)
            {
                return .success(
                    AutofocusRegion(region: region.oriented(forExifOrientation: orientation)))
            }
        } else {
            inspected.append(.init(path: "{Exif}.SubjectArea", finding: .missing))
        }

        // The ImageIO paths found nothing. Sony records AF in private maker notes ImageIO
        // never exposes, so re-read the container with focusmeta before reporting the gap.
        return regionsFromMetadataFile(of: url, inspected: inspected, make: make)
    }

    /// What focusmeta concluded about one file, in the few facts the evidence path needs.
    /// focusmeta's report is a large struct with an internal memberwise initializer, so the
    /// bridge reduces it to this public-value summary; tests state summaries directly and the
    /// real-container suites exercise the reduction over synthetic bytes.
    public struct FocusMetadataConclusion: Sendable, Equatable {
        /// The camera focusmeta recognized, if any.
        let vendor: CameraVendor?
        /// The camera model, for a short Sony evidence path.
        let model: String?
        /// The recorded camera make string.
        let recordedMake: String?
        /// The focus record focusmeta read, if the container carried one.
        let focus: RecordedFocus?
        /// The display-space geometry focusmeta derived, when orientation was unambiguous.
        let displayGeometry: FocusGeometry?
        /// focusmeta's overall outcome.
        let status: ExtractionStatus
    }

    /// Reduces one focusmeta report to the facts the bridge uses.
    public static func conclusion(of report: FocusMetadataReport) -> FocusMetadataConclusion {
        FocusMetadataConclusion(
            vendor: report.camera?.vendor,
            model: report.camera?.model,
            recordedMake: report.camera?.make,
            focus: report.focus,
            displayGeometry: report.displayGeometry,
            status: report.status)
    }

    /// focusmeta, whose direct container parsing fills the Sony gap, consulted only after both
    /// ImageIO paths reported missing — the proven Fuji, Panasonic and Apple readings keep
    /// their route untouched.
    ///
    /// focusmeta's `displayGeometry` is already rotated for display; it is normalized against
    /// its own display extent and used directly, without applying Clove's orientation map
    /// again (that double application is exactly the mirrored-overlay bug the synthetic
    /// orientation tests pin down). A stored-space-only report, another vendor's raw
    /// observations, or any absence of geometry maps to explicit unavailability with focusmeta's
    /// own facts as evidence — never a guess and never silence.
    func regionsFromMetadataFile(
        of url: URL, inspected: [AutofocusMetadataEvidence.Inspection], make: String?
    ) -> Result<AutofocusRegion, AutofocusMetadataEvidence> {
        guard let conclusion = metadataFiles.readMetadataFile(at: url) else {
            return .failure(
                AutofocusMetadataEvidence(
                    inspected: inspected, cameraMake: make, exifOrientation: 1))
        }
        if let region = conclusion.displayGeometry.flatMap(Self.region(from:)) {
            return .success(AutofocusRegion(region: region))
        }
        return .failure(
            AutofocusMetadataEvidence(
                inspected: inspected + [Self.focusmetaInspection(conclusion)], cameraMake: make,
                exifOrientation: 1))
    }

    /// What focusmeta concluded, as one evidence entry. Sony's verified scope is named
    /// plainly; every other vendor's raw observations map to the explicit unavailability
    /// focusmeta itself reports.
    static func focusmetaInspection(
        _ conclusion: FocusMetadataConclusion
    ) -> AutofocusMetadataEvidence.Inspection {
        let vendor = conclusion.vendor
        let make = conclusion.recordedMake.map { " (\($0))" } ?? ""
        switch vendor {
        case .sony:
            let camera = conclusion.model.map { " \($0)" } ?? ""
            let reason = Self.sonyUnavailabilityReason(conclusion)
            return .init(
                path: "focusmeta.SonyMakerNote\(camera)", finding: .unreadable(reason))
        case .fujifilm, .panasonic:
            return .init(
                path: "focusmeta.\(vendor.map(\.rawValue) ?? "vendor")MakerNote\(make)",
                finding: .unreadable(
                    "geometry semantics unverified; ImageIO's reading above is the proven one"))
        case nil:
            return .init(
                path: "focusmeta.container\(make)",
                finding: .unreadable(
                    "unrecognized container or vendor; no geometry"))
        default:
            return .init(
                path: "focusmeta.\(vendor.map(\.rawValue) ?? "vendor")MakerNote\(make)",
                finding: .unreadable("geometry semantics unverified for this vendor"))
        }
    }

    /// The short reason focusmeta could not present Sony geometry: its unavailability case,
    /// or — when the container parsed but no focus record exists at all — that absence.
    private static func sonyUnavailabilityReason(
        _ conclusion: FocusMetadataConclusion
    ) -> String {
        if case .unavailable(let reason)? = conclusion.focus?.geometry {
            return "Sony focus geometry unavailable: \(reason)"
        }
        if conclusion.focus == nil {
            return conclusion.status == .focusMetadataMissing
                ? "no focus record" : "focus record not interpretable"
        }
        return "display orientation not established"
    }

    /// focusmeta's display-space geometry as a display-space ``NormalizedRegion``: centered,
    /// normalized against the display extent the library already rotated, and clipped into the
    /// visible frame the way the proven paths clip. A point-only location gets the small box
    /// the UI already presents for tiny regions; the scorer reports `regionTooSmall` where it
    /// truly is. An out-of-frame geometry is not evidence Clove can locate.
    static func region(from geometry: FocusGeometry) -> NormalizedRegion? {
        switch geometry {
        case .region(let region):
            return Self.region(
                centerX: region.normalizedCenter.x, centerY: region.normalizedCenter.y,
                width: region.normalizedSize.width, height: region.normalizedSize.height)
        case .location(let location):
            return Self.region(
                centerX: location.normalizedCenter.x, centerY: location.normalizedCenter.y,
                width: locatedRegionSize, height: locatedRegionSize)
        case .unavailable:
            return nil
        }
    }

    /// The size presented for a located point with no recorded extent, so a point the camera
    /// recorded is drawn rather than hidden.
    static let locatedRegionSize = 0.03

    private static func region(
        centerX: Double, centerY: Double, width: Double, height: Double
    ) -> NormalizedRegion? {
        guard centerX.isFinite, centerY.isFinite, width.isFinite, height.isFinite,
            centerX >= 0, centerX <= 1, centerY >= 0, centerY <= 1, width > 0, height > 0
        else { return nil }
        let region = NormalizedRegion(
            x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        guard region.x >= -0.0001, region.y >= -0.0001,
            region.x + region.width <= 1.0001, region.y + region.height <= 1.0001
        else { return nil }
        return NormalizedRegion(
            x: min(max(region.x, 0), 1 - region.width),
            y: min(max(region.y, 0), 1 - region.height),
            width: region.width, height: region.height)
    }

    /// `[x, y, width, height, "f"|"t"]` with corner + size semantics. The Fuji fixture repeats
    /// the tuple twice; both entries are required to agree, and the Panasonic fixture's single
    /// tuple centers at the 49-point grid's exact middle, confirming the corner reading.
    static func afInfoRegion(_ raw: Any) -> NormalizedRegion? {
        guard let values = raw as? [Any] else { return nil }
        var tuples: [[Double]] = []
        var index = 0
        while index + 5 <= values.count {
            let quad = values[index..<(index + 4)].compactMap { $0 as? Double }
            // The trailing flag of each tuple is the strings "f" or "t"; a tuple without
            // its flag is a different writer's shape and is rejected whole.
            guard let flag = values[index + 4] as? String, flag == "f" || flag == "t",
                quad.count == 4
            else { return nil }
            tuples.append(quad)
            index += 5
        }
        guard index == values.count, !tuples.isEmpty else { return nil }
        guard tuples.allSatisfy({ $0 == tuples[0] }) else { return nil }
        let x = tuples[0][0]
        let y = tuples[0][1]
        let width = tuples[0][2]
        let height = tuples[0][3]
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0,
            x >= 0, y >= 0, x + width <= 1.0001, y + height <= 1.0001
        else { return nil }
        return NormalizedRegion(x: x, y: y, width: min(width, 1 - x), height: min(height, 1 - y))
    }

    /// `[centerX, centerY, width, height]` in pixels. The Apple fixture's values (2009, 1506,
    /// 2318, 1390 in 4032×3024) sit exactly at the frame's dead center as a center rect, which
    /// orientation 6 must display as dead center too, and overflow the frame as a corner rect.
    static func subjectAreaRegion(_ raw: Any, pixelWidth: Int, pixelHeight: Int)
        -> NormalizedRegion?
    {
        guard let values = raw as? [Any], let x = values.count > 0 ? values[0] as? Int : nil,
            values.count > 1, let y = values[1] as? Int,
            pixelWidth > 0, pixelHeight > 0
        else { return nil }
        guard values.count == 2 || values.count == 4 else { return nil }
        let width = values.count == 4 ? (values[2] as? Int) ?? -1 : 1
        let height = values.count == 4 ? (values[3] as? Int) ?? -1 : 1
        guard width > 0, height > 0 else { return nil }
        let frameWidth = Double(pixelWidth)
        let frameHeight = Double(pixelHeight)
        let halfWidth = Double(width) / 2
        let halfHeight = Double(height) / 2
        let region = NormalizedRegion(
            x: (Double(x) - halfWidth) / frameWidth, y: (Double(y) - halfHeight) / frameHeight,
            width: Double(width) / frameWidth, height: Double(height) / frameHeight)
        // Clamp into the frame; a center outside the frame is not evidence Clove can locate.
        guard region.x >= -0.05, region.y >= -0.05,
            region.x + region.width <= 1.05, region.y + region.height <= 1.05
        else { return nil }
        let clamped = NormalizedRegion(
            x: min(max(region.x, 0), 1 - region.width),
            y: min(max(region.y, 0), 1 - region.height),
            width: region.width, height: region.height)
        return clamped
    }
}
