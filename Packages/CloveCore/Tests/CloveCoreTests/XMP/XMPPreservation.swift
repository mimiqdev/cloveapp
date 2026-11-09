import Foundation
import ImageIO

/// Test-only proofs that do not use the codec's own ranges.
enum XMPPreservation {
    /// The packet with Clove's owned marks removed, byte for byte.
    ///
    /// Both sides of a round trip are reduced the same way, so equal results prove that no
    /// byte outside the owned properties changed. The reducer is deliberately independent
    /// of the codec: it finds every prefix bound to the XMP namespace and strips the
    /// `Rating`/`Label` attributes and property elements written with it. A description
    /// that was self-closing and had to be expanded for a new property is folded back to
    /// its self-closing form, since that expansion is the only non-property byte an
    /// insertion may add.
    static func outsideOwnedMarks(_ data: Data) throws -> String {
        var text = String(decoding: data, as: UTF8.self)
        for prefix in try xmpPrefixes(in: text) {
            let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
            let name = "\(escapedPrefix):(?:Rating|Label)"
            let patterns = [
                "\\s+\(name)\\s*=\\s*(\"[^\"]*\"|'[^']*')",
                "<\(name)(?:\\s[^>]*)?/>",
                "<\(name)(?:\\s[^>]*)?>[^<]*</\(name)>",
            ]
            for pattern in patterns {
                let expression = try NSRegularExpression(pattern: pattern)
                text = expression.stringByReplacingMatches(
                    in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }
        let expansion = try NSRegularExpression(
            pattern: "(<rdf:Description[^>]*)></rdf:Description>")
        return expansion.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1/>")
    }

    private static func xmpPrefixes(in text: String) throws -> [String] {
        let pattern =
            #"xmlns:([A-Za-z_][A-Za-z0-9_.\-]*)\s*=\s*["']http://ns\.adobe\.com/xap/1\.0/["']"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let prefixRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[prefixRange])
        }
    }
}

/// Independent reading through ImageIO, which is not the codec under test.
enum XMPImageIOReader {
    /// `xmp:Rating` and `xmp:Label` as ImageIO reads them, or `nil` when it refuses.
    static func marks(from data: Data) -> (rating: String?, label: String?)? {
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
            return nil
        }
        let rating =
            CGImageMetadataCopyStringValueWithPath(
                metadata, nil, "xmp:Rating" as CFString) as String?
        let label =
            CGImageMetadataCopyStringValueWithPath(
                metadata, nil, "xmp:Label" as CFString) as String?
        return (rating, label)
    }
}
