import Foundation

/// One validated XMP packet, with byte ranges into the bytes it was read from.
///
/// The packet keeps every original byte; edits splice only the ranges Clove owns. Values
/// come from `XMLParser`, which validates well-formedness and resolves entities, while the
/// ranges come from `XMPTokenizer` (G1 XMP codec row; PRD P0-07).
struct XMPPacket {
    /// An expanded XML name: namespace URI plus local name. A prefix is only spelling.
    struct Name: Hashable {
        let namespace: String
        let localName: String
    }

    /// A validated element with its byte ranges and in-scope namespace prefixes.
    struct Element {
        let name: Name
        /// The qualified name as written, reused when an element is rewritten.
        let qualifiedName: String
        /// Attributes other than namespace declarations, keyed by expanded name.
        let attributes: [Name: String]
        /// Byte ranges for the attributes in `attributes`.
        let attributeSpans: [Name: AttributeSpan]
        /// The start tag, including its closing `>`.
        let startTag: Range<Int>
        /// The whole element, including its end tag.
        let whole: Range<Int>
        /// The bytes between the tags; `nil` when self-closing.
        let content: Range<Int>?
        /// Prefixes in scope at this element, including its own declarations.
        let prefixes: [String: String]
        let parent: Int?
        var children: [Int] = []
        /// Character data directly inside this element, with entities resolved.
        var text = ""

        var isSelfClosing: Bool { content == nil }
    }

    /// The byte ranges of one attribute.
    struct AttributeSpan {
        /// The whitespace before the name through the closing quote.
        let full: Range<Int>
        /// The bytes between the quotes.
        let value: Range<Int>
    }

    static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let xmlNamespace = "http://www.w3.org/XML/1998/namespace"

    static let rdfDescriptionName = Name(namespace: rdfNamespace, localName: "Description")
    static let rdfRDFName = Name(namespace: rdfNamespace, localName: "RDF")
    static let rdfAboutName = Name(namespace: rdfNamespace, localName: "about")
    static let rdfNodeIDName = Name(namespace: rdfNamespace, localName: "nodeID")
    static let rdfIDName = Name(namespace: rdfNamespace, localName: "ID")

    let bytes: [UInt8]
    let elements: [Element]
    /// Top-level `rdf:Description` elements, in document order.
    let descriptions: [Int]

    init(_ data: Data) throws {
        guard !data.isEmpty else { throw XMPCodecError.emptyPacket }
        guard data.count <= XMPCodec.maximumPacketSize else {
            throw XMPCodecError.packetTooLarge(
                limit: XMPCodec.maximumPacketSize, byteCount: data.count)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw XMPCodecError.unsupportedEncoding
        }
        let bytes = Array(data)
        try Self.validateEncodingDeclaration(in: bytes)
        let rawElements = try XMPTokenizer.elements(in: bytes)

        let builder = XMPPacketBuilder(rawElements: rawElements)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        let parsed = parser.parse()
        if let failure = builder.failure { throw failure }
        guard parsed else {
            throw XMPCodecError.malformedXML(
                parser.parserError?.localizedDescription ?? "Invalid XML")
        }
        guard builder.nextToken == rawElements.count else {
            throw XMPCodecError.malformedXML("Markup and parsed document disagree")
        }

        var elements = builder.elements
        for (index, element) in elements.enumerated() {
            if let parent = element.parent {
                elements[parent].children.append(index)
            }
        }
        let descriptions = elements.indices.filter { index in
            guard elements[index].name == Self.rdfDescriptionName,
                let parent = elements[index].parent
            else { return false }
            return elements[parent].name == Self.rdfRDFName
        }
        self.bytes = bytes
        self.elements = elements
        self.descriptions = descriptions
    }

    /// Refuses a declaration that names an encoding other than UTF-8.
    ///
    /// The bytes are already valid UTF-8, so a packet that declares UTF-16 or Latin-1 is
    /// contradictory; PRD P0-07 sidecars are read as UTF-8 only (G1 XMP codec row).
    private static func validateEncodingDeclaration(in bytes: [UInt8]) throws {
        var index = 0
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
        let declarationStart: [UInt8] = Array("<?xml".utf8)
        guard index + declarationStart.count <= bytes.count,
            Array(bytes[index..<(index + declarationStart.count)]) == declarationStart
        else { return }
        guard let close = bytes[(index + declarationStart.count)...].firstIndex(of: 0x3E) else {
            return
        }
        let declaration = String(decoding: bytes[index..<close], as: UTF8.self)
        guard let encoding = Self.declaredEncoding(in: declaration) else { return }
        let normalized = encoding.uppercased()
        guard normalized == "UTF-8" || normalized == "UTF8" else {
            throw XMPCodecError.unsupportedEncoding
        }
    }

    private static func declaredEncoding(in declaration: String) -> String? {
        guard let marker = declaration.range(of: "encoding", options: [.caseInsensitive]) else {
            return nil
        }
        var rest = declaration[marker.upperBound...]
        rest = rest.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        guard rest.first == "=" else { return nil }
        rest = rest.dropFirst()
        rest = rest.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        rest = rest.dropFirst()
        guard let close = rest.firstIndex(of: quote) else { return nil }
        return String(rest[rest.startIndex..<close])
    }

    /// The owned property an expanded name names, if any.
    static func property(named name: Name) -> XMPProperty? {
        guard name.namespace == XMPProperty.namespaceURI else { return nil }
        switch name.localName {
        case "Rating": return .rating
        case "Label": return .label
        default: return nil
        }
    }
}

/// Builds the validated element tree from `XMLParser` callbacks and tokenizer ranges.
private final class XMPPacketBuilder: NSObject, XMLParserDelegate {
    private let rawElements: [XMPRawElement]
    private(set) var nextToken = 0
    private(set) var elements: [XMPPacket.Element] = []
    private(set) var failure: XMPCodecError?
    private var stack: [Int] = []
    private var scopes: [[String: String]] = [
        [
            "xml": XMPPacket.xmlNamespace
        ]
    ]

    init(rawElements: [XMPRawElement]) {
        self.rawElements = rawElements
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        guard failure == nil else { return }
        guard nextToken < rawElements.count else {
            fail(XMPCodecError.malformedXML("Markup has fewer elements than the parsed document"))
            parser.abortParsing()
            return
        }
        let raw = rawElements[nextToken]
        nextToken += 1
        guard raw.qualifiedName == elementName else {
            fail(
                XMPCodecError.malformedXML("Markup and parsed document disagree at \(elementName)"))
            parser.abortParsing()
            return
        }
        var scope = scopes.last ?? [:]
        for (name, value) in attributeDict {
            if name == "xmlns" {
                scope[""] = value
            } else if name.hasPrefix("xmlns:") {
                scope[String(name.dropFirst("xmlns:".count))] = value
            }
        }
        do {
            let name = try Self.resolve(elementName, in: scope)
            var resolved: [XMPPacket.Name: String] = [:]
            var spans: [XMPPacket.Name: XMPPacket.AttributeSpan] = [:]
            for (qualified, value) in attributeDict {
                if qualified == "xmlns" || qualified.hasPrefix("xmlns:") { continue }
                let attributeName = try Self.resolve(qualified, in: scope, isAttribute: true)
                if let property = XMPPacket.property(named: attributeName) {
                    guard resolved[attributeName] == nil else {
                        throw XMPCodecError.duplicateMark(property)
                    }
                } else {
                    guard resolved[attributeName] == nil else {
                        throw XMPCodecError.malformedXML("Duplicate attribute \(qualified)")
                    }
                }
                guard
                    let rawAttribute = raw.attributes.first(where: {
                        $0.qualifiedName == qualified
                    })
                else {
                    throw XMPCodecError.malformedXML("Attribute ranges disagree with the document")
                }
                resolved[attributeName] = value
                spans[attributeName] = XMPPacket.AttributeSpan(
                    full: rawAttribute.full, value: rawAttribute.value)
            }
            let element = XMPPacket.Element(
                name: name, qualifiedName: elementName, attributes: resolved,
                attributeSpans: spans, startTag: raw.startTag, whole: raw.whole,
                content: raw.content, prefixes: scope, parent: stack.last)
            elements.append(element)
            stack.append(elements.count - 1)
            scopes.append(scope)
        } catch let error as XMPCodecError {
            fail(error)
            parser.abortParsing()
        } catch {
            fail(XMPCodecError.malformedXML("\(error)"))
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
        _ = scopes.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let last = stack.last else { return }
        elements[last].text += string
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        guard let last = stack.last else { return }
        elements[last].text += whitespaceString
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let last = stack.last else { return }
        elements[last].text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?
    ) {
        fail(XMPCodecError.entityDeclaration)
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?,
        systemID: String?
    ) {
        fail(XMPCodecError.entityDeclaration)
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?,
        systemID: String?, notationName: String?
    ) {
        fail(XMPCodecError.entityDeclaration)
        parser.abortParsing()
    }

    private func fail(_ error: XMPCodecError) {
        if failure == nil { failure = error }
    }

    /// Resolves a qualified name against the prefixes in scope.
    ///
    /// Namespace identity, not prefix spelling, decides whether an attribute is a Clove
    /// mark, so a packet may bind any prefix to the XMP namespace (PRD disk rule 4).
    private static func resolve(
        _ qualified: String, in scope: [String: String], isAttribute: Bool = false
    ) throws -> XMPPacket.Name {
        guard let colon = qualified.firstIndex(of: ":") else {
            let namespace = isAttribute ? "" : (scope[""] ?? "")
            return XMPPacket.Name(namespace: namespace, localName: qualified)
        }
        let prefix = String(qualified[qualified.startIndex..<colon])
        let localName = String(qualified[qualified.index(after: colon)...])
        guard let namespace = scope[prefix] else {
            throw XMPCodecError.malformedXML("Unbound namespace prefix \(prefix)")
        }
        return XMPPacket.Name(namespace: namespace, localName: localName)
    }
}
