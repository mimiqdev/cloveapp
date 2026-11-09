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
        if case .set(let rating) = edit.rating {
            propertyLines.append("   <xmp:Rating>\(rating.rawValue)</xmp:Rating>")
            expected.rating = .rated(rating)
        }
        if case .set(let label) = edit.label, !label.isClear {
            let escaped = try XMPText.elementText(label.rawValue)
            propertyLines.append("   <xmp:Label>\(escaped)</xmp:Label>")
            expected.label = label
        }

        var lines = [
            "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>",
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">",
            " <rdf:RDF xmlns:rdf=\"\(XMPPacket.rdfNamespace)\">",
        ]
        if propertyLines.isEmpty {
            lines.append(
                "  <rdf:Description rdf:about=\"\" xmlns:xmp=\"\(XMPProperty.namespaceURI)\"/>")
        } else {
            lines.append(
                "  <rdf:Description rdf:about=\"\" xmlns:xmp=\"\(XMPProperty.namespaceURI)\">")
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
