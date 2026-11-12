import CoreGraphics
import Foundation
import ImageIO

/// The property paths one file was inspected for, and what was found, so an unavailable answer
/// can show its evidence instead of an unexplained empty result (#208).
public struct AutofocusMetadataEvidence: Error, Sendable, Equatable {
    public enum Finding: Sendable, Equatable {
        /// The path was not present in the file's properties.
        case missing
        /// The path was present but its shape was not understood; the raw description is kept.
        case unreadable(String)
    }

    /// One inspected property path and what was found in it.
    public struct Inspection: Sendable, Equatable {
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

/// Reads camera autofocus regions from ImageIO's property dictionaries.
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
/// host's SDK has no Sony dictionary at all — so a Sony file reports every path missing rather
/// than a guessed reading of undocumented bytes.
public struct AutofocusMetadataReader: Sendable {
    public init() {}

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

        return .failure(
            AutofocusMetadataEvidence(
                inspected: inspected, cameraMake: make, exifOrientation: orientation))
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
