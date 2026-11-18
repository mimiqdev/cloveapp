import Foundation

extension XMPCodec {
    /// Builds the packet used when a photo has no sidecar yet.
    ///
    /// The result is a minimal standard XMP packet: the `xpacket` wrapper with the BOM and
    /// the conventional identifier, `x:xmpmeta`, `rdf:RDF`, and one `rdf:Description` with
    /// `rdf:about=""` holding only the requested marks. PRD P0-07 and How marks reach disk,
    /// rule 3 reuse an existing sidecar whenever one exists, so this path only runs when
    /// no packet bytes were supplied.
    static func newPacket(for edit: XMPEdit) throws -> Data {
        var propertyLines: [String] = []
        var expected = XMPMarks()
        var namespaces = "xmlns:xmp=\"\(XMPProperty.namespaceURI)\""

        if case .set(let rating) = edit.rating {
            propertyLines.append("   <xmp:Rating>\(rating.rawValue)</xmp:Rating>")
            expected.rating = .rated(rating)
        }
        if case .set(let label) = edit.label, !label.isClear {
            let escaped = try XMPText.elementText(label.rawValue)
            propertyLines.append("   <xmp:Label>\(escaped)</xmp:Label>")
            expected.label = label
        }
        if case .set(let rawKeywords) = edit.keywords {
            for keyword in rawKeywords {
                try XMPText.validate(keyword, error: .unsupportedKeywordText)
            }
            let keywords = PhotoKeywords.deduplicated(rawKeywords)
            if !keywords.isEmpty {
                namespaces += " xmlns:dc=\"\(XMPProperty.dublinCoreNamespaceURI)\""
                propertyLines.append("   <dc:subject>")
                propertyLines.append("    <rdf:Bag>")
                for keyword in keywords {
                    let escaped = try XMPText.elementText(keyword, error: .unsupportedKeywordText)
                    propertyLines.append("     <rdf:li>\(escaped)</rdf:li>")
                }
                propertyLines.append("    </rdf:Bag>")
                propertyLines.append("   </dc:subject>")
                expected.keywords = keywords
            }
        }

        var lines = [
            "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>",
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">",
            " <rdf:RDF xmlns:rdf=\"\(XMPPacket.rdfNamespace)\">",
        ]
        if propertyLines.isEmpty {
            lines.append(
                "  <rdf:Description rdf:about=\"\" \(namespaces)/>")
        } else {
            lines.append(
                "  <rdf:Description rdf:about=\"\" \(namespaces)>")
            lines.append(contentsOf: propertyLines)
            lines.append("  </rdf:Description>")
        }
        lines.append(" </rdf:RDF>")
        lines.append("</x:xmpmeta>")
        lines.append("<?xpacket end=\"w\"?>")
        lines.append("")
        let data = Data(lines.joined(separator: "\n").utf8)

        // PRD P0-08 and G1's read-back rule: never return bytes that do not read back.
        guard try XMPPacket(data).read() == expected else {
            throw XMPCodecError.writeVerificationFailed
        }
        return data
    }
}
