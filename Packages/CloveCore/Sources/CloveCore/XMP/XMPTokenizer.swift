import Foundation

/// One attribute inside a start tag, with byte ranges relative to the packet.
struct XMPRawAttribute {
    /// The qualified name as written, for example `rdf:about`.
    let qualifiedName: String
    /// The whitespace before the name through the closing quote, so removing the
    /// attribute leaves no double space behind.
    let full: Range<Int>
    /// The bytes between the quotes.
    let value: Range<Int>
}

/// One element as found by the byte scanner, before namespace resolution.
struct XMPRawElement {
    /// The qualified name as written, for example `xmp:Rating`.
    let qualifiedName: String
    let attributes: [XMPRawAttribute]
    /// The start tag, including the closing `>`.
    let startTag: Range<Int>
    /// The start tag through the end tag; filled in when the end tag is reached.
    var whole: Range<Int>
    /// The bytes between the tags; `nil` when self-closing.
    var content: Range<Int>?
}

/// A byte scanner that finds element and attribute ranges without rewriting anything.
///
/// Foundation's `XMLParser` validates well-formedness and decodes values, but it does not
/// report where in the packet a value sits. This scanner supplies only those byte ranges,
/// so an edit can splice the owned value and keep every other byte (G1 XMP codec row).
/// Comments, CDATA sections and processing instructions are consumed as units so a `>` or
/// a quote inside them never looks like markup.
enum XMPTokenizer {
    private static let lessThan: UInt8 = 0x3C
    private static let greaterThan: UInt8 = 0x3E
    private static let slash: UInt8 = 0x2F
    private static let question: UInt8 = 0x3F
    private static let exclamation: UInt8 = 0x21
    private static let hyphen: UInt8 = 0x2D
    private static let equals: UInt8 = 0x3D
    private static let doubleQuote: UInt8 = 0x22
    private static let singleQuote: UInt8 = 0x27
    private static let openBracket: UInt8 = 0x5B

    private static let commentClose: [UInt8] = [hyphen, hyphen, greaterThan]
    private static let cdataOpen: [UInt8] = [
        lessThan, exclamation, openBracket, 0x43, 0x44, 0x41, 0x54, 0x41, openBracket,
    ]
    private static let cdataClose: [UInt8] = [0x5D, 0x5D, greaterThan]
    private static let instructionClose: [UInt8] = [question, greaterThan]

    /// Scans `bytes` and returns every element with its byte ranges.
    static func elements(in bytes: [UInt8]) throws -> [XMPRawElement] {
        var elements: [XMPRawElement] = []
        var open: [Int] = []
        var index = 0
        while index < bytes.count {
            guard let tagStart = bytes[index...].firstIndex(of: lessThan) else { break }
            index = tagStart
            if matches(bytes, at: index, [lessThan, exclamation, hyphen, hyphen]) {
                guard let close = find(bytes, commentClose, from: index + 4) else {
                    throw XMPCodecError.malformedXML("Unterminated comment")
                }
                index = close + commentClose.count
            } else if matches(bytes, at: index, cdataOpen) {
                guard let close = find(bytes, cdataClose, from: index + cdataOpen.count) else {
                    throw XMPCodecError.malformedXML("Unterminated CDATA section")
                }
                index = close + cdataClose.count
            } else if matches(bytes, at: index, Array("<!DOCTYPE".utf8)) {
                throw XMPCodecError.documentTypeDeclaration
            } else if matches(bytes, at: index, Array("<!ENTITY".utf8)) {
                throw XMPCodecError.entityDeclaration
            } else if matches(bytes, at: index, [lessThan, exclamation]) {
                throw XMPCodecError.malformedXML("Unsupported markup declaration")
            } else if matches(bytes, at: index, [lessThan, question]) {
                guard let close = find(bytes, instructionClose, from: index + 2) else {
                    throw XMPCodecError.malformedXML("Unterminated processing instruction")
                }
                index = close + instructionClose.count
            } else if matches(bytes, at: index, [lessThan, slash]) {
                index = try scanEndTag(bytes, at: index, elements: &elements, open: &open)
            } else {
                index = try scanStartTag(bytes, at: index, elements: &elements, open: &open)
            }
        }
        guard open.isEmpty else {
            throw XMPCodecError.malformedXML("The packet ends inside an element")
        }
        return elements
    }

    private static func scanStartTag(
        _ bytes: [UInt8], at start: Int, elements: inout [XMPRawElement], open: inout [Int]
    ) throws -> Int {
        var cursor = start + 1
        let nameStart = cursor
        while cursor < bytes.count, !isWhitespace(bytes[cursor]), bytes[cursor] != greaterThan,
            bytes[cursor] != slash
        {
            cursor += 1
        }
        guard cursor > nameStart else {
            throw XMPCodecError.malformedXML("Empty element name")
        }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self)

        var attributes: [XMPRawAttribute] = []
        var selfClosing = false
        var tagEnd: Int?
        while cursor < bytes.count {
            let whitespaceStart = cursor
            while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
            if cursor < bytes.count, bytes[cursor] == slash {
                guard cursor + 1 < bytes.count, bytes[cursor + 1] == greaterThan else {
                    throw XMPCodecError.malformedXML("Malformed self-closing tag")
                }
                selfClosing = true
                tagEnd = cursor + 2
                cursor += 2
                break
            }
            if cursor < bytes.count, bytes[cursor] == greaterThan {
                tagEnd = cursor + 1
                cursor += 1
                break
            }
            guard cursor < bytes.count else { break }
            let attributeStart = cursor
            while cursor < bytes.count, !isWhitespace(bytes[cursor]),
                bytes[cursor] != equals, bytes[cursor] != greaterThan, bytes[cursor] != slash
            {
                cursor += 1
            }
            guard cursor > attributeStart else {
                throw XMPCodecError.malformedXML("Malformed attribute name")
            }
            let attributeName = String(decoding: bytes[attributeStart..<cursor], as: UTF8.self)
            while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
            guard cursor < bytes.count, bytes[cursor] == equals else {
                throw XMPCodecError.malformedXML("Attribute without a value")
            }
            cursor += 1
            while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
            guard cursor < bytes.count,
                bytes[cursor] == doubleQuote || bytes[cursor] == singleQuote
            else {
                throw XMPCodecError.malformedXML("Unquoted attribute value")
            }
            let quote = bytes[cursor]
            cursor += 1
            let valueStart = cursor
            while cursor < bytes.count, bytes[cursor] != quote { cursor += 1 }
            guard cursor < bytes.count else {
                throw XMPCodecError.malformedXML("Unterminated attribute value")
            }
            let value = valueStart..<cursor
            cursor += 1
            attributes.append(
                XMPRawAttribute(
                    qualifiedName: attributeName, full: whitespaceStart..<cursor, value: value))
        }
        guard let tagEnd else {
            throw XMPCodecError.malformedXML("Unterminated start tag")
        }
        let startTag = start..<tagEnd
        let elementIndex = elements.count
        elements.append(
            XMPRawElement(
                qualifiedName: name, attributes: attributes, startTag: startTag,
                whole: startTag, content: nil))
        if !selfClosing { open.append(elementIndex) }
        return tagEnd
    }

    private static func scanEndTag(
        _ bytes: [UInt8], at start: Int, elements: inout [XMPRawElement], open: inout [Int]
    ) throws -> Int {
        var cursor = start + 2
        let nameStart = cursor
        while cursor < bytes.count, !isWhitespace(bytes[cursor]), bytes[cursor] != greaterThan {
            cursor += 1
        }
        guard cursor > nameStart else {
            throw XMPCodecError.malformedXML("Empty end tag")
        }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self)
        while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
        guard cursor < bytes.count, bytes[cursor] == greaterThan else {
            throw XMPCodecError.malformedXML("Malformed end tag")
        }
        let endTagEnd = cursor + 1
        guard let elementIndex = open.popLast() else {
            throw XMPCodecError.malformedXML("Unexpected end tag")
        }
        guard elements[elementIndex].qualifiedName == name else {
            throw XMPCodecError.malformedXML("Mismatched end tag \(name)")
        }
        elements[elementIndex].whole = elements[elementIndex].startTag.lowerBound..<endTagEnd
        elements[elementIndex].content = elements[elementIndex].startTag.upperBound..<start
        return endTagEnd
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func matches(_ bytes: [UInt8], at index: Int, _ pattern: [UInt8]) -> Bool {
        guard index >= 0, index + pattern.count <= bytes.count else { return false }
        for offset in 0..<pattern.count where bytes[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    private static func find(_ bytes: [UInt8], _ pattern: [UInt8], from index: Int) -> Int? {
        guard !pattern.isEmpty, index >= 0, index <= bytes.count - pattern.count else {
            return nil
        }
        var candidate = index
        while candidate <= bytes.count - pattern.count {
            if matches(bytes, at: candidate, pattern) { return candidate }
            candidate += 1
        }
        return nil
    }
}
