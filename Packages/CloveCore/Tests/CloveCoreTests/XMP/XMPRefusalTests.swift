import Foundation
import Testing

import CloveCore

private let requestedLabel = ColourLabel(colour: .green)

private func requestedEdit() throws -> XMPEdit {
    XMPEdit(rating: .set(try #require(Rating(rawValue: 3))), label: .set(requestedLabel))
}

/// Requires both reading and writing to refuse, with the expected case.
private func expectRefusal(_ packet: Data, _ matches: (XMPCodecError) -> Bool) throws {
    let readError = try #require(xmpError { _ = try xmpCodec.read(packet) })
    #expect(matches(readError), "read refused with \(readError)")
    let writeError = try #require(
        xmpError { _ = try xmpCodec.write(try requestedEdit(), into: packet) })
    #expect(matches(writeError), "write refused with \(writeError)")
}

@Test func refusesAnEmptyPresentFile() throws {
    #expect(xmpError { _ = try xmpCodec.read(Data()) } == .emptyPacket)
    #expect(
        xmpError { _ = try xmpCodec.write(XMPEdit(label: .set(requestedLabel)), into: Data()) }
            == .emptyPacket)
    // No sidecar at all is different from an empty one: that path creates a packet.
    #expect(try xmpCodec.read(nil) == .unmarked)
}

@Test func refusesMalformedXML() throws {
    let truncated = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
            "fixtures/xmp/malformed.xmp"))
    try expectRefusal(truncated, isMalformedXML)

    let mismatched = xmpPacket("<rdf:Description rdf:about=\"\"></rdf:RDF>")
    try expectRefusal(mismatched, isMalformedXML)

    let unclosed = Data(
        "<?xpacket begin=\"\u{FEFF}\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\">".utf8)
    try expectRefusal(unclosed, isMalformedXML)
}

@Test func refusesDocumentTypeDeclarations() throws {
    let classic = Data(
        """
        <?xml version="1.0"?>
        <!DOCTYPE xmpmeta>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""/>
         </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    try expectRefusal(classic) { $0 == .documentTypeDeclaration }

    // An internal subset is refused before any entity expansion reaches the parser.
    let billionLaughs = Data(
        """
        <?xml version="1.0"?>
        <!DOCTYPE lolz [
         <!ENTITY lol "lol">
         <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
         <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
        ]>
        <lolz>&lol3;</lolz>
        """.utf8)
    try expectRefusal(billionLaughs) { $0 == .documentTypeDeclaration }
}

@Test func refusesEntityDeclarations() throws {
    let entity = Data(
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <!ENTITY writer "Clove">
        </x:xmpmeta>
        """.utf8)
    try expectRefusal(entity) { $0 == .entityDeclaration }
}

@Test func refusesNonUTF8Bytes() throws {
    let packet = xmpDescriptionPacket(attributes: "xmp:Rating=\"3\"")
    let text = String(decoding: packet, as: UTF8.self)
    let utf16 = try #require(text.data(using: .utf16LittleEndian))
    try expectRefusal(utf16) { $0 == .unsupportedEncoding }
    let bigEndian = try #require(text.data(using: .utf16BigEndian))
    try expectRefusal(bigEndian) { $0 == .unsupportedEncoding }

    // A byte that is not valid UTF-8 at all.
    var latin1 = Data()
    latin1.append(contentsOf: Array("<rdf:Description rdf:about=\"\"><xmp:Label>".utf8))
    latin1.append(0xE9)
    latin1.append(contentsOf: Array("</xmp:Label></rdf:Description>".utf8))
    try expectRefusal(latin1) { $0 == .unsupportedEncoding }
}

@Test func refusesAnotherDeclaredEncoding() throws {
    let packet = xmpDescriptionPacket(attributes: "xmp:Rating=\"3\"")
    let declared = Data(
        ("""
        <?xml version="1.0" encoding="ISO-8859-1"?>
        """ + String(decoding: packet, as: UTF8.self)).utf8)
    try expectRefusal(declared) { $0 == .unsupportedEncoding }

    // A UTF-8 declaration is accepted.
    let utf8 = Data(
        ("""
        <?xml version="1.0" encoding="utf-8"?>
        """ + String(decoding: packet, as: UTF8.self)).utf8)
    #expect(try xmpCodec.read(utf8).rating == .rated(try #require(Rating(rawValue: 3))))
}

@Test func refusesAPacketOverTheSizeLimit() throws {
    let oversized = Data(repeating: 0x20, count: XMPCodec.maximumPacketSize + 1)
    try expectRefusal(oversized) {
        $0 == .packetTooLarge(limit: XMPCodec.maximumPacketSize, byteCount: oversized.count)
    }

    // A packet exactly at the limit is still readable; padding after the packet is legal.
    var atLimit = xmpDescriptionPacket(attributes: "xmp:Rating=\"2\"")
    atLimit.append(Data(repeating: 0x20, count: XMPCodec.maximumPacketSize - atLimit.count))
    #expect(atLimit.count == XMPCodec.maximumPacketSize)
    #expect(try xmpCodec.read(atLimit).rating == .rated(try #require(Rating(rawValue: 2))))
}

@Test func refusesAPacketWithoutADescription() throws {
    let packet = Data(
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"/>
        </x:xmpmeta>
        """.utf8)
    try expectRefusal(packet) { $0 == .missingDescription }
}

@Test func refusesDuplicateMarksInOneDescription() throws {
    let attributeAndElement = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"3\"", body: "<xmp:Rating>4</xmp:Rating>")
    try expectRefusal(attributeAndElement) { $0 == .duplicateMark(.rating) }

    let twoElements = xmpDescriptionPacket(
        body: """
              <xmp:Label>Red</xmp:Label>
              <xmp:Label>Blue</xmp:Label>
            """)
    try expectRefusal(twoElements) { $0 == .duplicateMark(.label) }

    // Two prefixes, one expanded name: still the same property.
    let twoPrefixes = xmpDescriptionPacket(
        namespaces: """
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:photo="http://ns.adobe.com/xap/1.0/"
            """,
        attributes: "xmp:Rating=\"3\" photo:Rating=\"4\"")
    try expectRefusal(twoPrefixes) { $0 == .duplicateMark(.rating) }
}

@Test func refusesMarksInSeveralDescriptions() throws {
    let packet = xmpPacket(
        """
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="3"/>
          <rdf:Description rdf:about="#step" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="4"/>
        """)
    try expectRefusal(packet) { $0 == .marksInSeveralDescriptions }
}

@Test func readsSeveralUnmarkedDescriptionsButRefusesToWrite() throws {
    let packet = xmpPacket(
        """
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:CreatorTool="Other"/>
          <rdf:Description rdf:about="#step"
            xmlns:stEvt="http://ns.adobe.com/xap/1.0/sType/ResourceEvent#"
            stEvt:action="saved"/>
        """)
    #expect(try xmpCodec.read(packet) == .unmarked)
    #expect(
        xmpError { _ = try xmpCodec.write(XMPEdit(label: .set(requestedLabel)), into: packet) }
            == .ambiguousDescriptions)
}

@Test func readsAQualifiedDescriptionButRefusesToWrite() throws {
    for identity in ["rdf:about=\"#step\"", "rdf:nodeID=\"n1\"", "rdf:ID=\"step\""] {
        let packet = xmpPacket(
            """
              <rdf:Description \(identity) xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmp:Rating="4" xmp:Label="Red"/>
            """)
        #expect(try xmpCodec.read(packet).rating == .rated(try #require(Rating(rawValue: 4))))
        #expect(
            xmpError { _ = try xmpCodec.write(XMPEdit(label: .set(requestedLabel)), into: packet) }
                == .qualifiedDescription, "\(identity)")
    }
}

@Test func refusesQualifiedAndStructuredMarks() throws {
    let shapes: [(String, XMPProperty)] = [
        ("<xmp:Rating rdf:resource=\"https://example.com/rating\"/>", .rating),
        ("<xmp:Rating rdf:parseType=\"Resource\"><xmp:Note>3</xmp:Note></xmp:Rating>", .rating),
        (
            "<xmp:Rating rdf:datatype=\"http://www.w3.org/2001/XMLSchema#integer\">3</xmp:Rating>",
            .rating
        ),
        ("<xmp:Label xml:lang=\"en\">Green</xmp:Label>", .label),
        ("<xmp:Label><xmp:Text>Green</xmp:Text></xmp:Label>", .label),
    ]
    for (body, property) in shapes {
        let packet = xmpDescriptionPacket(body: body)
        try expectRefusal(packet) { $0 == .qualifiedMark(property) }
    }
}

@Test func refusesMarksOutsideATopLevelDescription() throws {
    let nestedElement = xmpDescriptionPacket(
        namespaces: """
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:acme="https://example.com/ns/acme/1.0/"
            """,
        body: "<acme:Settings><xmp:Rating>3</xmp:Rating></acme:Settings>")
    try expectRefusal(nestedElement) { $0 == .misplacedMark(.rating) }

    let nestedDescription = xmpDescriptionPacket(
        namespaces: """
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:acme="https://example.com/ns/acme/1.0/"
            """,
        body: """
              <acme:Project rdf:parseType="Resource">
               <rdf:Description xmp:Rating="3"/>
              </acme:Project>
            """)
    try expectRefusal(nestedDescription) { $0 == .misplacedMark(.rating) }
}

@Test func refusesUnboundNamespacePrefixes() throws {
    let packet = Data(
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""><photo:Rating>3</photo:Rating></rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    try expectRefusal(packet, isMalformedXML)
}

@Test(arguments: ["abc", "3.5", "", "5 stars", "1e3"])
func refusesNonIntegerRatings(text: String) throws {
    let packet = xmpDescriptionPacket(body: "<xmp:Rating>\(text)</xmp:Rating>")
    try expectRefusal(packet) { $0 == .invalidRating(text) }
}

@Test func refusesLabelTextXMLCannotCarry() throws {
    let packet = xmpDescriptionPacket(attributes: "xmp:Rating=\"1\"")
    let unrepresentable = ColourLabel(rawValue: "bad\u{0000}text")
    #expect(
        xmpError { _ = try xmpCodec.write(XMPEdit(label: .set(unrepresentable)), into: packet) }
            == .unsupportedLabelText)
    #expect(
        xmpError { _ = try xmpCodec.write(XMPEdit(label: .set(unrepresentable)), into: nil) }
            == .unsupportedLabelText)
}

@Test func refusesNonXMLBytes() throws {
    try expectRefusal(Data("not xml at all".utf8), isMalformedXML)
    try expectRefusal(Data("   ".utf8), isMalformedXML)
}

@Test func refusesAnEmptyRatingElement() throws {
    // A rating is an integer; an empty element is not "unrated", it is a broken value.
    try expectRefusal(xmpDescriptionPacket(body: "<xmp:Rating/>")) {
        $0 == .invalidRating("")
    }
}
