import Foundation

/// Writing: change only the owned value bytes and leave everything else in place.
///
/// The editor never reserializes the packet. It replaces or removes the exact bytes of the
/// rating and label it was asked to change, and inserts a new property element when the
/// description has none (G1 XMP codec row).
extension XMPPacket {
    /// A byte replacement; the write applies them from the end of the packet backwards.
    private struct Splice {
        let range: Range<Int>
        let replacement: [UInt8]
    }

    /// Builds or replaces the `<dc:subject>` element body, inserting `<rdf:Bag><rdf:li>...</rdf:li></rdf:Bag>`.
    private enum InsertValue {
        case scalar(String)
        case keywords([String])
    }

    /// Applies one edit and returns the new packet bytes.
    ///
    /// Refusals: everything `analyze()` refuses, plus a description that names another
    /// resource, or several descriptions with no marked one, so no mark placement is
    /// provable. The written packet is read back before any bytes are returned (PRD P0-08).
    func applying(_ edit: XMPEdit) throws -> Data {
        let analyzed = try analyze()
        guard let targetIndex = analyzed.description else {
            throw XMPCodecError.ambiguousDescriptions
        }
        let target = elements[targetIndex]
        guard !Self.isQualified(target) else {
            throw XMPCodecError.qualifiedDescription
        }

        var splices: [Splice] = []
        var inserts: [XMPProperty: InsertValue] = [:]

        if case .set(let rating) = edit.rating {
            let text = String(rating.rawValue)
            if let location = analyzed.rating {
                splices.append(try Self.replacement(of: location, with: text))
            } else {
                inserts[.rating] = .scalar(text)
            }
        }

        switch edit.label {
        case .keep:
            break
        case .set(let label):
            if label.isClear {
                if let location = analyzed.label {
                    splices.append(Self.removal(of: location))
                }
            } else {
                let text = label.rawValue
                try XMPText.validate(text)
                if let location = analyzed.label {
                    splices.append(try Self.replacement(of: location, with: text))
                } else {
                    inserts[.label] = .scalar(text)
                }
            }
        }

        if case .set(let rawKeywords) = edit.keywords {
            for keyword in rawKeywords {
                try XMPText.validate(keyword, error: .unsupportedKeywordText)
            }
            let newKeywords = PhotoKeywords.deduplicated(rawKeywords)
            if newKeywords.isEmpty {
                if let location = analyzed.keywords {
                    splices.append(Self.removal(of: location))
                }
            } else if let location = analyzed.keywords {
                if location.keywords != newKeywords {
                    splices.append(try Self.bagReplacement(of: location, with: newKeywords))
                }
            } else {
                inserts[.keywords] = .keywords(newKeywords)
            }

            let removed = Set(analyzed.marks.keywords).subtracting(newKeywords)
            if !removed.isEmpty {
                for hierarchical in analyzed.hierarchicalSubjects {
                    let matchingEntries = hierarchical.entries.filter { entry in
                        let components = entry.text.split(
                            separator: "|", omittingEmptySubsequences: false
                        ).map(String.init)
                        return removed.contains(entry.text)
                            || components.contains(where: removed.contains)
                    }
                    if matchingEntries.isEmpty {
                        continue
                    } else if matchingEntries.count == hierarchical.entries.count {
                        splices.append(Splice(range: hierarchical.whole, replacement: []))
                    } else {
                        for entry in matchingEntries {
                            splices.append(Splice(range: entry.whole, replacement: []))
                        }
                    }
                }
            }
        }

        if !inserts.isEmpty {
            splices.append(try Self.insertion(of: inserts, into: target))
        }
        return try Self.applying(
            splices, to: bytes, expected: Self.expectedMarks(analyzed.marks, edit))
    }

    private static func replacement(of location: MarkLocation, with text: String) throws -> Splice {
        switch location.form {
        case .attribute(let span):
            return Splice(
                range: span.value, replacement: Array(try XMPText.attributeValue(text).utf8))
        case .element(let content, let whole, let qualifiedName):
            if let content {
                return Splice(
                    range: content, replacement: Array(try XMPText.elementText(text).utf8))
            }
            // Expand `/>` in place so the start tag, including any namespace declaration
            // written on the mark itself, stays byte for byte.
            let escaped = try XMPText.elementText(text)
            let end = whole.upperBound
            return Splice(
                range: (end - 2)..<end,
                replacement: Array(">\(escaped)</\(qualifiedName)>".utf8))
        case .bagElement:
            preconditionFailure("bagElement must be replaced via bagReplacement")
        }
    }

    private static func bagReplacement(of location: MarkLocation, with keywords: [String]) throws
        -> Splice
    {
        guard
            case .bagElement(let content, let whole, let qualifiedName, let prefixes) = location
                .form
        else {
            preconditionFailure("bagReplacement requires bagElement form")
        }
        let body = try Self.rdfBagElement(keywords: keywords, in: prefixes)
        if let content {
            return Splice(range: content, replacement: Array(body.utf8))
        }
        let end = whole.upperBound
        return Splice(
            range: (end - 2)..<end,
            replacement: Array(">\(body)</\(qualifiedName)>".utf8))
    }

    private static func removal(of location: MarkLocation) -> Splice {
        switch location.form {
        case .attribute(let span):
            return Splice(range: span.full, replacement: [])
        case .element(_, let whole, _), .bagElement(_, let whole, _, _):
            return Splice(range: whole, replacement: [])
        }
    }

    /// Builds the property elements for marks the description did not have yet.
    ///
    /// A self-closing description is expanded in place; every other child stays untouched.
    private static func insertion(of inserts: [XMPProperty: InsertValue], into target: Element)
        throws
        -> Splice
    {
        var properties = String()
        for property in XMPProperty.allCases {
            guard let value = inserts[property] else { continue }
            let name = Self.elementName(for: property, in: target.prefixes)
            let qualified = name.qualified
            let declaration = name.declaration
            switch value {
            case .scalar(let text):
                let escaped = try XMPText.elementText(text)
                properties += "<\(qualified)\(declaration)>\(escaped)</\(qualified)>"
            case .keywords(let keywords):
                var scope = target.prefixes
                if !declaration.isEmpty,
                    declaration.contains("xmlns:\(property.preferredPrefix)=")
                {
                    scope[property.preferredPrefix] = property.propertyNamespaceURI
                }
                let body = try Self.rdfBagElement(keywords: keywords, in: scope)
                properties += "<\(qualified)\(declaration)>\(body)</\(qualified)>"
            }
        }
        if target.isSelfClosing {
            let range = (target.startTag.upperBound - 2)..<target.startTag.upperBound
            let expanded = ">\(properties)</\(target.qualifiedName)>"
            return Splice(range: range, replacement: Array(expanded.utf8))
        }
        let range = target.startTag.upperBound..<target.startTag.upperBound
        return Splice(range: range, replacement: Array(properties.utf8))
    }

    /// Chooses how a newly inserted property is named.
    ///
    /// A prefix already bound to the property's namespace is reused, preferring its conventional
    /// prefix; otherwise the element declares the namespace URI itself, so no prefix can collide
    /// with one another app already uses (PRD disk rule 4; prefix spelling is not identity).
    private static func elementName(
        for property: XMPProperty, in scope: [String: String]
    ) -> (qualified: String, declaration: String) {
        let namespaceURI = property.propertyNamespaceURI
        let preferred = property.preferredPrefix
        let prefixes = scope.filter { !$0.key.isEmpty && $0.value == namespaceURI }
        let prefix: String?
        if prefixes[preferred] != nil {
            prefix = preferred
        } else {
            prefix = prefixes.keys.sorted().first
        }
        if let prefix {
            return ("\(prefix):\(property.localName)", "")
        }
        // The usual prefix with a local declaration, unless another namespace owns
        // that spelling here; then the element declares the default namespace instead.
        if scope[preferred] == nil {
            return (
                "\(preferred):\(property.localName)",
                " xmlns:\(preferred)=\"\(namespaceURI)\""
            )
        }
        return (property.localName, " xmlns=\"\(namespaceURI)\"")
    }

    private static func rdfBagElement(keywords: [String], in scope: [String: String]) throws
        -> String
    {
        let rdfPrefixes = scope.filter { !$0.key.isEmpty && $0.value == XMPPacket.rdfNamespace }
        let rdfPrefix: String?
        if rdfPrefixes["rdf"] != nil {
            rdfPrefix = "rdf"
        } else {
            rdfPrefix = rdfPrefixes.keys.sorted().first
        }
        let bagOpen: String
        let bagClose: String
        let liTag: String
        if let rdfPrefix {
            bagOpen = "<\(rdfPrefix):Bag>"
            bagClose = "</\(rdfPrefix):Bag>"
            liTag = "\(rdfPrefix):li"
        } else if scope["rdf"] == nil {
            bagOpen = "<rdf:Bag xmlns:rdf=\"\(XMPPacket.rdfNamespace)\">"
            bagClose = "</rdf:Bag>"
            liTag = "rdf:li"
        } else {
            bagOpen = "<Bag xmlns=\"\(XMPPacket.rdfNamespace)\">"
            bagClose = "</Bag>"
            liTag = "li"
        }
        var items = String()
        for keyword in keywords {
            let escaped = try XMPText.elementText(keyword, error: .unsupportedKeywordText)
            items += "<\(liTag)>\(escaped)</\(liTag)>"
        }
        return "\(bagOpen)\(items)\(bagClose)"
    }

    private static func expectedMarks(_ marks: XMPMarks, _ edit: XMPEdit) -> XMPMarks {
        var expected = marks
        if case .set(let rating) = edit.rating { expected.rating = .rated(rating) }
        if case .set(let label) = edit.label { expected.label = label }
        if case .set(let keywords) = edit.keywords {
            expected.keywords = PhotoKeywords.deduplicated(keywords)
        }
        return expected
    }

    private static func applying(_ splices: [Splice], to bytes: [UInt8], expected: XMPMarks) throws
        -> Data
    {
        var output = bytes
        for splice in splices.sorted(by: {
            ($0.range.lowerBound, $0.range.upperBound)
                > ($1.range.lowerBound, $1.range.upperBound)
        }) {
            output.replaceSubrange(splice.range, with: splice.replacement)
        }
        let data = Data(output)
        // PRD P0-08: a change is only real once it reads back as requested.
        guard try XMPPacket(data).read() == expected else {
            throw XMPCodecError.writeVerificationFailed
        }
        return data
    }
}
