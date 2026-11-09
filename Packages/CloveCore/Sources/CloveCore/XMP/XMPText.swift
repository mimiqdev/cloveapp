import Foundation

/// Escaping for the two XML positions Clove writes an owned value into.
///
/// Clove writes only the value of a rating or label property, so every other byte of the
/// packet stays as another app left it (G1 XMP codec row; PRD P0-07). Labels keep their
/// exact external text, including unknown text and non-ASCII characters (PRD disk rule 9),
/// so escaping never normalizes or trims the value.
enum XMPText {
    /// Escapes text for an element body such as `<xmp:Label>Green</xmp:Label>`.
    static func elementText(_ text: String) throws -> String {
        try validate(text)
        var escaped = String()
        escaped.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            // Escaping '>' also keeps a literal "]]>" out of the element body.
            case ">": escaped += "&gt;"
            // XML normalizes a literal carriage return to a newline; a reference does not.
            case "\r": escaped += "&#13;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Escapes text for an attribute value inside either quote style.
    ///
    /// Character references are used for tab, newline and carriage return because XML
    /// attribute-value normalization would turn the literal characters into spaces.
    static func attributeValue(_ text: String) throws -> String {
        try validate(text)
        var escaped = String()
        escaped.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            case "\t": escaped += "&#9;"
            case "\n": escaped += "&#10;"
            case "\r": escaped += "&#13;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Rejects text XML 1.0 cannot represent at all, as no escaping can carry it.
    ///
    /// Swift strings cannot hold unpaired surrogates, so only the control characters,
    /// U+FFFE and U+FFFF remain. Writing them would emit a packet other parsers refuse,
    /// which would break the read-back guarantee in PRD P0-08.
    static func validate(_ text: String) throws {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                continue
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                continue
            default:
                throw XMPCodecError.unsupportedLabelText
            }
        }
    }
}
