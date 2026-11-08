import Foundation

/// A small inspection tree, deliberately separate from the ImageIO codec.
/// Ranges are UTF-16 offsets into the original packet so edits preserve other bytes.
struct XMPDocument {
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let xmp = "http://ns.adobe.com/xap/1.0/"
    static let clove = "https://clove.photo/ns/1.0/"

    final class Node {
        var name: String
        var qualifiedName: String
        var attributes: [String: String]
        var namespaces: [String: String]
        var children: [Node] = []
        var text = ""
        var opening: NSRange
        var whole: NSRange
        var rawAttributes: [String: NSRange]

        init(
            name: String, qualifiedName: String, attributes: [String: String],
            namespaces: [String: String], token: Token
        ) {
            self.name = name
            self.qualifiedName = qualifiedName
            self.attributes = attributes
            self.namespaces = namespaces
            opening = token.opening
            whole = token.whole
            rawAttributes = token.attributes
        }

        var isDescription: Bool { name == XMPDocument.key(XMPDocument.rdf, "Description") }

        /// Semantic comparison: description attributes and property elements have
        /// the same meaning; property order is irrelevant, Seq order is significant.
        func canonical(semantic: Bool, excludingMarks: Bool) -> String {
            var attrs = attributes
            // Serializer identification belongs to the envelope, not photo data.
            if semantic && name == XMPDocument.key("adobe:ns:meta/", "xmpmeta") {
                attrs.removeValue(forKey: XMPDocument.key("adobe:ns:meta/", "xmptk"))
            }
            if excludingMarks && isDescription {
                attrs = attrs.filter { !XMPDocument.markKeys.contains($0.key) }
            }
            var properties: [String] = []
            if semantic && isDescription {
                for (key, value) in attrs where !key.hasPrefix("{\(XMPDocument.rdf)}") {
                    properties.append("\(key)[]=\(String(reflecting: value)){}")
                    attrs.removeValue(forKey: key)
                }
            }
            var childValues = children.filter {
                !(excludingMarks && isDescription && XMPDocument.markKeys.contains($0.name))
            }.map { $0.canonical(semantic: semantic, excludingMarks: excludingMarks) }
            childValues += properties
            if semantic && name != XMPDocument.key(XMPDocument.rdf, "Seq") {
                childValues.sort()
            }
            let attrValues = attrs.sorted(by: { $0.key < $1.key }).map {
                "\($0.key)=\(String(reflecting: $0.value))"
            }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
                "\(name)[\(attrValues.joined(separator: ","))]=\(String(reflecting: value)){\(childValues.joined(separator: ";"))}"
        }
    }

    struct Token {
        var opening: NSRange
        var whole: NSRange
        var attributes: [String: NSRange]
    }

    let root: Node
    let descriptions: [Node]

    static func key(_ namespace: String, _ local: String) -> String { "{\(namespace)}\(local)" }
    static let markKeys = [key(xmp, "Rating"), key(xmp, "Label"), key(clove, "Reject")]

    init(_ data: Data) throws {
        guard let string = String(data: data, encoding: .utf8),
            !string.contains("<!DOCTYPE"), !string.contains("<!ENTITY")
        else { throw XMPError.invalidPacket("Only UTF-8 packets without DTDs are supported") }
        let delegate = try TreeBuilder(string)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root, !delegate.failed else {
            throw XMPError.invalidPacket(parser.parserError?.localizedDescription ?? "Invalid XML")
        }
        self.root = root
        descriptions = delegate.descriptions
        guard !descriptions.isEmpty else { throw XMPError.invalidPacket("No rdf:Description") }
    }

    func marks() throws -> XMPMarks {
        var values: [String: String] = [:]
        for node in descriptions {
            for key in Self.markKeys {
                let candidates =
                    [node.attributes[key]].compactMap { $0 }
                    + node.children.filter { $0.name == key }.map(\.text)
                for value in candidates {
                    guard values[key] == nil else {
                        throw XMPError.invalidPacket("Duplicate mark property")
                    }
                    values[key] = value
                }
            }
        }
        let ratingString = values[Self.markKeys[0]]
        let rating = ratingString.flatMap(Int.init) ?? 0
        guard ratingString.map({ Int($0) != nil }) ?? true, (-1...5).contains(rating) else {
            throw XMPError.invalidPacket("Invalid rating")
        }
        let reject = values[Self.markKeys[2]]?.lowercased()
        guard reject.map({ ["true", "false", "1", "0"].contains($0) }) ?? true else {
            throw XMPError.invalidPacket("Invalid Reject boolean")
        }
        return XMPMarks(
            rating: rating, label: values[Self.markKeys[1]] ?? "",
            reject: reject == "true" || reject == "1")
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: XMPDocument.Node?
    var descriptions: [XMPDocument.Node] = []
    var failed = false
    private var stack: [XMPDocument.Node] = []
    private var tokens: [XMPDocument.Token] = []
    private var nextToken = 0

    init(_ source: String) throws {
        super.init()
        let text = source as NSString
        // Quoted '>' characters, comments, CDATA, and processing instructions are
        // consumed as units; only element tags participate in the range stack.
        let expression = try NSRegularExpression(
            pattern:
                #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|</?[A-Za-z_](?:[^>"']|"[^"]*"|'[^']*')*>"#
        )
        let attribute = try NSRegularExpression(
            pattern: #"\s+([^\s=<>/]+)\s*=\s*("[^"]*"|'[^']*')"#)
        var indices: [Int] = []
        for match in expression.matches(
            in: source, range: NSRange(location: 0, length: text.length))
        {
            let tag = text.substring(with: match.range)
            if tag.hasPrefix("<?") || tag.hasPrefix("<!") { continue }
            if tag.hasPrefix("</") {
                guard let index = indices.popLast() else {
                    throw XMPError.invalidPacket("Unbalanced XML")
                }
                tokens[index].whole.length = NSMaxRange(match.range) - tokens[index].whole.location
            } else {
                var attributes: [String: NSRange] = [:]
                for attr in attribute.matches(
                    in: tag, range: NSRange(location: 0, length: (tag as NSString).length))
                {
                    let name = (tag as NSString).substring(with: attr.range(at: 1))
                    attributes[name] = NSRange(
                        location: match.range.location + attr.range.location,
                        length: attr.range.length)
                }
                tokens.append(
                    .init(opening: match.range, whole: match.range, attributes: attributes))
                if !tag.hasSuffix("/>") { indices.append(tokens.count - 1) }
            }
        }
        guard indices.isEmpty else { throw XMPError.invalidPacket("Unclosed XML") }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        guard nextToken < tokens.count else { failed = true; parser.abortParsing(); return }
        var namespaces = stack.last?.namespaces ?? ["xml": "http://www.w3.org/XML/1998/namespace"]
        for (name, value) in attributeDict {
            if name == "xmlns" { namespaces[""] = value }
            if name.hasPrefix("xmlns:") { namespaces[String(name.dropFirst(6))] = value }
        }
        func expanded(_ name: String, attribute: Bool) -> String {
            let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                guard let uri = namespaces[parts[0]] else { failed = true; return name }
                return XMPDocument.key(uri, parts[1])
            }
            return XMPDocument.key(attribute ? "" : namespaces[""] ?? "", name)
        }
        var attributes: [String: String] = [:]
        for (name, value) in attributeDict where name != "xmlns" && !name.hasPrefix("xmlns:") {
            attributes[expanded(name, attribute: true)] = value
        }
        let node = XMPDocument.Node(
            name: expanded(elementName, attribute: false), qualifiedName: elementName,
            attributes: attributes, namespaces: namespaces, token: tokens[nextToken])
        nextToken += 1
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        if node.isDescription { descriptions.append(node) }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }
    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) { _ = stack.popLast() }
}
