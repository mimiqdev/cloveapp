import Foundation
import ImageIO

public struct GroupingMetadata: Sendable {
    public var photo: GroupingPhoto
    public var milliseconds: Double
    /// Exact ImageIO property paths and XMP tag names for the fields inspected.
    public var properties: [String: String]
    public var selectedPaths: [String: String]
    public var error: String?
}

public enum GroupingMetadataReader {
    public static func read(url: URL, id: String) -> GroupingMetadata {
        let start = ContinuousClock.now
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            return GroupingMetadata(
                photo: .init(id: id, model: nil, serial: nil, captureTime: nil),
                milliseconds: elapsed(start), properties: [:], selectedPaths: [:],
                error: "ImageIO properties unavailable")
        }
        var flat: [String: String] = [:]
        flatten(properties, prefix: "", into: &flat)
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                if let value = CGImageMetadataTagCopyValue(tag) as? String {
                    flat["XMP.\(path)"] = value
                }
                return true
            }
        }
        var result = parse(flat: flat, id: id)
        result.milliseconds = elapsed(start)
        return result
    }

    /// Exposed for deterministic date/path tests without camera binaries.
    public static func parse(flat: [String: String], id: String) -> GroupingMetadata {
        var paths: [String: String] = [:]
        func pick(_ field: String, _ candidates: [String]) -> String? {
            for path in candidates {
                if let value = flat[path]?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !value.isEmpty
                {
                    paths[field] = path
                    return value
                }
            }
            return nil
        }
        let model = pick("model", ["{TIFF}.Model", "XMP.tiff:Model"])
        let serial = pick(
            "serial",
            [
                "{Exif}.BodySerialNumber", "{ExifAux}.SerialNumber", "XMP.exifEX:BodySerialNumber",
                "XMP.aux:SerialNumber", "{MakerCanon}.SerialNumber",
                "{MakerNikon}.SerialNumber", "{MakerNikon}.SerialNO",
                "{MakerFuji}.SerialNumber", "{MakerOlympus}.SerialNumber",
                "{MakerPanasonic}.SerialNumber", "{MakerSony}.SerialNumber",
                "{MakerPentax}.SerialNumber",
            ])
        let rawTime = pick(
            "time",
            [
                "{Exif}.DateTimeOriginal", "XMP.exif:DateTimeOriginal", "XMP.photoshop:DateCreated",
                "XMP.xmp:CreateDate",
            ])
        let subsecond = pick(
            "subsecond", ["{Exif}.SubsecTimeOriginal", "XMP.exif:SubsecTimeOriginal"])
        let offset = pick("offset", ["{Exif}.OffsetTimeOriginal", "XMP.exifEX:OffsetTimeOriginal"])
        let time = rawTime.flatMap { captureTime($0, subsecond: subsecond, offset: offset) }
        let relevant = flat.filter { path, _ in
            ["date", "time", "model", "serial", "body"].contains {
                path.lowercased().contains($0)
            }
        }
        return GroupingMetadata(
            photo: .init(id: id, model: model, serial: serial, captureTime: time),
            milliseconds: 0, properties: relevant, selectedPaths: paths,
            error: rawTime != nil && time == nil ? "Invalid capture time" : nil)
    }

    public static func captureTime(_ value: String, subsecond: String?, offset: String?) -> Date? {
        // XMP often includes its own fractional seconds and zone.
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        if let date = try? Date.ISO8601FormatStyle().parse(value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        // No offset: compare camera wall clocks in a fixed surrogate zone,
        // independent of the Mac/device locale. Never assume the local zone.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard value.count == 19, var date = formatter.date(from: value),
            formatter.string(from: date) == value
        else { return nil }
        if let subsecond, !subsecond.isEmpty {
            guard subsecond.allSatisfy({ $0.isASCII && $0.isNumber }),
                let fraction = Double("0." + subsecond)
            else { return nil }
            date.addTimeInterval(fraction)
        }
        if let offset {
            let characters = Array(offset)
            guard characters.count == 6, characters[0] == "+" || characters[0] == "-",
                characters[3] == ":",
                let hours = Int(String(characters[1...2])),
                let minutes = Int(String(characters[4...5])), hours <= 23, minutes <= 59
            else { return nil }
            let sign = characters[0] == "+" ? 1.0 : -1.0
            date.addTimeInterval(-sign * Double(hours * 3_600 + minutes * 60))
        }
        return date
    }

    private static func flatten(
        _ dictionary: [String: Any], prefix: String, into flat: inout [String: String]
    ) {
        for (key, value) in dictionary {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                flatten(nested, prefix: path, into: &flat)
            } else if let string = value as? String {
                flat[path] = string
            } else if let number = value as? NSNumber {
                flat[path] = number.stringValue
            }
        }
    }

    static func elapsed(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }
}
