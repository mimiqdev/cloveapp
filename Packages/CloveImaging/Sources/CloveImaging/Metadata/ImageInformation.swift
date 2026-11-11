import Foundation
import ImageIO

/// Read-only information for a photo's Info sheet (handoff Detail, G1 folder access).
/// Missing or malformed fields stay nil. Reading this value never decodes image pixels.
public struct ImageInformation: Sendable, Equatable {
    public let captureWallTime: Date?
    public let subseconds: String?
    public let camera: String?
    public let bodySerial: String?
    public let lens: String?
    public let exposureSeconds: Double?
    public let aperture: Double?
    public let iso: Int?
    public let focalLengthMillimetres: Double?
    public let fileSizeBytes: Int64?
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init(
        captureWallTime: Date? = nil, subseconds: String? = nil, camera: String? = nil,
        bodySerial: String? = nil, lens: String? = nil, exposureSeconds: Double? = nil,
        aperture: Double? = nil, iso: Int? = nil, focalLengthMillimetres: Double? = nil,
        fileSizeBytes: Int64? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil
    ) {
        self.captureWallTime = captureWallTime
        self.subseconds = subseconds
        self.camera = camera
        self.bodySerial = bodySerial
        self.lens = lens
        self.exposureSeconds = exposureSeconds
        self.aperture = aperture
        self.iso = iso
        self.focalLengthMillimetres = focalLengthMillimetres
        self.fileSizeBytes = fileSizeBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// On-demand property and size reads for Info. Call off the main actor inside the folder session.
public struct ImageInformationReader: Sendable {
    public init() {}

    /// Reads only properties of the primary image, with ImageIO caching disabled (G1).
    /// An unreadable image returns nil. Optional file-size failures do not hide valid metadata.
    public func read(url: URL) -> ImageInformation? {
        guard !Task.isCancelled, url.isFileURL else { return nil }
        return autoreleasepool {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                    as? [String: Any], !Task.isCancelled
            else { return nil }
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return ImageInformationParser.parse(properties: properties, fileSize: size)
        }
    }
}

/// The property boundary shared by the real reader and deterministic tests.
enum ImageInformationParser {
    static func parse(properties: [String: Any], fileSize: Int?) -> ImageInformation {
        let metadata = MetadataParser.parse(
            properties: properties, creationDate: nil, modificationDate: nil)
        let exif = properties["{Exif}"] as? [String: Any] ?? [:]
        let auxiliary = properties["{ExifAux}"] as? [String: Any] ?? [:]
        let sensitivity = (exif["ISOSpeedRatings"] as? [Any])?.first
        return ImageInformation(
            captureWallTime: metadata.captureTime.value?.wallTime,
            subseconds: metadata.subseconds.value,
            camera: metadata.model.value, bodySerial: metadata.bodySerial.value,
            lens: text(exif["LensModel"]) ?? text(auxiliary["LensModel"]),
            exposureSeconds: positiveNumber(exif["ExposureTime"]),
            aperture: positiveNumber(exif["FNumber"]),
            iso: positiveInteger(sensitivity),
            focalLengthMillimetres: positiveNumber(exif["FocalLength"]),
            fileSizeBytes: fileSize.flatMap { $0 >= 0 ? Int64($0) : nil },
            pixelWidth: positiveInteger(properties["PixelWidth"]),
            pixelHeight: positiveInteger(properties["PixelHeight"]))
    }

    private static func text(_ raw: Any?) -> String? {
        guard let string = raw as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func positiveNumber(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.doubleValue
        return value.isFinite && value > 0 ? value : nil
    }

    private static func positiveInteger(_ raw: Any?) -> Int? {
        guard let value = positiveNumber(raw), value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(exactly: value)
    }
}
