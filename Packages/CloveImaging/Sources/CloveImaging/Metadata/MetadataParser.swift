import Foundation

/// Parses ImageIO properties without consulting TIFF modification time or guessing a zone.
/// Internal so deterministic tests can exercise malformed properties without camera binaries.
enum MetadataParser {
    static func parse(
        properties: [String: Any], creationDate: Date?, modificationDate: Date?
    ) -> ImageMetadata {
        let original = text(properties, paths: ["{Exif}.DateTimeOriginal"])
        let subseconds = digits(
            text(
                properties, paths: ["{Exif}.SubsecTimeOriginal"], unknownPlaceholderIsMissing: true)
        )
        let offset = offset(
            text(
                properties, paths: ["{Exif}.OffsetTimeOriginal"], unknownPlaceholderIsMissing: true)
        )
        let capture = capture(original, subseconds: subseconds, offset: offset)
        return ImageMetadata(
            captureTime: capture, subseconds: subseconds, utcOffset: offset,
            model: text(properties, paths: ["{TIFF}.Model"]),
            bodySerial: text(
                properties,
                paths: [
                    "{Exif}.BodySerialNumber", "{ExifAux}.SerialNumber",
                    "{MakerCanon}.SerialNumber", "{MakerNikon}.SerialNumber",
                    "{MakerNikon}.SerialNO", "{MakerFuji}.SerialNumber",
                    "{MakerOlympus}.SerialNumber", "{MakerPanasonic}.SerialNumber",
                    "{MakerSony}.SerialNumber", "{MakerPentax}.SerialNumber",
                ]),
            fileCreationTime: fileDate(creationDate, source: .fileCreation),
            fileModificationTime: fileDate(modificationDate, source: .fileModification))
    }

    private static func text(
        _ properties: [String: Any], paths: [String], unknownPlaceholderIsMissing: Bool = false
    ) -> MetadataField<String> {
        var firstInvalid: MetadataField<String>?
        for path in paths {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            guard let dictionary = properties[parts[0]] as? [String: Any],
                let raw = dictionary[parts[1]]
            else { continue }
            let source = MetadataLocation.imageProperty(path)
            let string: String
            if let value = raw as? String {
                string = value.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                string = number.stringValue
            } else {
                firstInvalid =
                    firstInvalid ?? .invalid(rawValue: String(describing: raw), source: source)
                continue
            }
            // EXIF permits spaces for unknown optional time values, including "   :  ".
            if unknownPlaceholderIsMissing, string.allSatisfy({ $0 == " " || $0 == ":" }) {
                continue
            }
            guard !string.isEmpty else {
                firstInvalid = firstInvalid ?? .invalid(rawValue: string, source: source)
                continue
            }
            return .value(string, source: source)
        }
        return firstInvalid ?? .missing
    }

    private static func digits(_ field: MetadataField<String>) -> MetadataField<String> {
        guard case .value(let value, let source) = field else { return field }
        guard value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return .invalid(rawValue: value, source: source)
        }
        return field
    }

    private static func offset(_ field: MetadataField<String>) -> MetadataField<Int> {
        switch field {
        case .missing: return .missing
        case .invalid(let raw, let source): return .invalid(rawValue: raw, source: source)
        case .value(let value, let source):
            let bytes = Array(value.utf8)
            guard bytes.count == 6, bytes[0] == 43 || bytes[0] == 45, bytes[3] == 58,
                [bytes[1], bytes[2], bytes[4], bytes[5]].allSatisfy({ (48...57).contains($0) }),
                let hours = Int(String(value.dropFirst().prefix(2))),
                let minutes = Int(String(value.suffix(2))), hours <= 23, minutes <= 59
            else { return .invalid(rawValue: value, source: source) }
            return .value((bytes[0] == 43 ? 1 : -1) * (hours * 3600 + minutes * 60), source: source)
        }
    }

    private static func capture(
        _ original: MetadataField<String>, subseconds: MetadataField<String>,
        offset: MetadataField<Int>
    ) -> MetadataField<CaptureTime> {
        switch original {
        case .missing: return .missing
        case .invalid(let raw, let source): return .invalid(rawValue: raw, source: source)
        case .value(let value, let source):
            // Exact ASCII EXIF shape; DateFormatter alone accepts some shortened fields.
            let bytes = Array(value.utf8)
            let separators: [Int: UInt8] = [4: 58, 7: 58, 10: 32, 13: 58, 16: 58]
            guard bytes.count == 19,
                bytes.enumerated().allSatisfy({ index, byte in
                    if let separator = separators[index] { return byte == separator }
                    return (48...57).contains(byte)
                })
            else { return .invalid(rawValue: value, source: source) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.isLenient = false
            guard var wallTime = formatter.date(from: value),
                formatter.string(from: wallTime) == value
            else {
                return .invalid(rawValue: value, source: source)
            }
            // Optional precision/zone failures remain visible on their own fields.
            // A valid original date still supplies capture order and grouping time.
            if let digits = subseconds.value, let fraction = Double("0." + digits) {
                wallTime.addTimeInterval(fraction)
            }
            return .value(
                CaptureTime(wallTime: wallTime, utcOffsetSeconds: offset.value), source: source)
        }
    }

    private static func fileDate(_ date: Date?, source: MetadataLocation) -> MetadataField<Date> {
        guard let date else { return .missing }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            return .invalid(rawValue: String(describing: date), source: source)
        }
        return .value(date, source: source)
    }
}
