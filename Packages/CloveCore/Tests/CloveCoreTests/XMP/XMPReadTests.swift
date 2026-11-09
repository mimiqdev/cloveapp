import Foundation
import Testing

import CloveCore

let xmpCodec = XMPCodec()

@Test func readsMarksInAttributeForm() throws {
    let packet = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"3\" xmp:Label=\"Green\"",
        body: """
            <dc:subject xmlns:dc="http://purl.org/dc/elements/1.1/">
             <rdf:Bag><rdf:li>keep me</rdf:li></rdf:Bag>
            </dc:subject>
            """)
    let marks = try xmpCodec.read(packet)
    #expect(marks.rating == .rated(try #require(Rating(rawValue: 3))))
    #expect(marks.label == ColourLabel(colour: .green))
}

@Test func readsMarksInElementForm() throws {
    let packet = xmpDescriptionPacket(
        body: """
              <xmp:Rating>4</xmp:Rating>
              <xmp:Label>Blue</xmp:Label>
            """)
    let marks = try xmpCodec.read(packet)
    #expect(marks.rating == .rated(try #require(Rating(rawValue: 4))))
    #expect(marks.label == ColourLabel(colour: .blue))
}

@Test func readsMarksByNamespaceURIAndNotByPrefix() throws {
    // Any prefix bound to the XMP namespace names the owned properties (PRD disk rule 4).
    let aliased = xmpDescriptionPacket(
        namespaces: "xmlns:photo=\"http://ns.adobe.com/xap/1.0/\"",
        attributes: "photo:Rating=\"2\" photo:Label=\"Orange\"")
    let marks = try xmpCodec.read(aliased)
    #expect(marks.rating == .rated(try #require(Rating(rawValue: 2))))
    #expect(marks.label == ColourLabel(colour: .orange))

    // The literal prefix `xmp` means nothing when it is bound to another namespace.
    let impostor = xmpDescriptionPacket(
        namespaces: "xmlns:xmp=\"https://example.com/not-xmp/\"",
        attributes: "xmp:Rating=\"5\" xmp:Label=\"Red\"")
    #expect(try xmpCodec.read(impostor) == .unmarked)
}

@Test func readsAbsentMarksAsUnmarked() throws {
    let packet = xmpDescriptionPacket(
        body: "<xmp:CreatorTool>Another app</xmp:CreatorTool>")
    #expect(try xmpCodec.read(packet) == .unmarked)
    #expect(try xmpCodec.read(nil) == .unmarked)
}

@Test(arguments: [-1, -2, 6, 7, 42])
func readsOutOfRangeRatingsAsExternal(value: Int) throws {
    let packet = xmpDescriptionPacket(attributes: "xmp:Rating=\"\(value)\"")
    let marks = try xmpCodec.read(packet)
    #expect(marks.rating == .external(value))
    #expect(marks.rating.rating == nil)
    #expect(marks.rating.externalValue == value)
}

@Test(arguments: LabelColour.allCases)
func readsEveryKnownColourName(colour: LabelColour) throws {
    let packet = xmpDescriptionPacket(attributes: "xmp:Label=\"\(colour.rawValue)\"")
    let label = try xmpCodec.read(packet).label
    #expect(label == ColourLabel(colour: colour))
    #expect(label.colour == colour)
}

@Test(arguments: [
    "\u{6A59}\u{8272}", "cafe\u{301}", "A & B", "  Green  ", "Green\n", "NOT a label",
])
func readsUnknownLabelTextExactly(text: String) throws {
    let escaped =
        text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: "\n", with: "&#10;")
    let packet = xmpDescriptionPacket(attributes: "xmp:Label=\"\(escaped)\"")
    let label = try xmpCodec.read(packet).label
    #expect(Array(label.rawValue.utf8) == Array(text.utf8))
    #expect(label.colour == nil)
}

@Test func readsElementRatingWithSurroundingWhitespace() throws {
    // XMP Rating is an XML Schema integer, so whitespace around the digits is insignificant.
    let packet = xmpDescriptionPacket(
        body: """
              <xmp:Rating>
               5
              </xmp:Rating>
            """)
    #expect(try xmpCodec.read(packet).rating == .rated(try #require(Rating(rawValue: 5))))
}

@Test func readsElementLabelWithoutTrimming() throws {
    // A label is exact external text: PRD disk rule 9 forbids trimming it.
    let packet = xmpDescriptionPacket(body: "<xmp:Label>  Green  </xmp:Label>")
    #expect(try xmpCodec.read(packet).label == ColourLabel(rawValue: "  Green  "))
}

@Test func readsEmptyDescriptionAsUnmarked() throws {
    let packet = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
            "fixtures/xmp/empty-description.xmp"))
    #expect(try xmpCodec.read(packet) == .unmarked)
}

@Test func readsSeveralDescriptionsWhenOneHoldsTheMarks() throws {
    let packet = xmpPacket(
        """
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="4" xmp:Label="Purple"/>
          <rdf:Description rdf:about="#history-step"
            xmlns:stEvt="http://ns.adobe.com/xap/1.0/sType/ResourceEvent#"
            stEvt:action="saved"/>
        """)
    let marks = try xmpCodec.read(packet)
    #expect(marks.rating == .rated(try #require(Rating(rawValue: 4))))
    #expect(marks.label == ColourLabel(colour: .purple))
}

@Test func readsPacketWithUTF8ByteOrderMark() throws {
    var packet = Data([0xEF, 0xBB, 0xBF])
    packet.append(xmpDescriptionPacket(attributes: "xmp:Rating=\"1\""))
    #expect(try xmpCodec.read(packet).rating == .rated(try #require(Rating(rawValue: 1))))
}

@Test func readsPastCommentsCDATAAndQuotedMarkup() throws {
    // A comment, CDATA and a quoted `>` must not be mistaken for owned properties.
    let packet = xmpDescriptionPacket(
        namespaces: """
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:dc="http://purl.org/dc/elements/1.1/"
            """,
        attributes: "xmp:Rating=\"2\"",
        body: """
            <!-- <xmp:Rating>5</xmp:Rating> xmp:Label="Red" -->
            <dc:description><rdf:Alt><rdf:li xml:lang="x-default"><![CDATA[<xmp:Label>Green</xmp:Label>]]></rdf:li></rdf:Alt></dc:description>
            <dc:source>a &gt; b</dc:source>
            """)
    let marks = try xmpCodec.read(packet)
    #expect(marks.rating == .rated(try #require(Rating(rawValue: 2))))
    #expect(marks.label == .clear)
}

@Test func readsALabelFromCDATAText() throws {
    let packet = xmpDescriptionPacket(body: "<xmp:Label><![CDATA[Green & <Blue>]]></xmp:Label>")
    #expect(try xmpCodec.read(packet).label == ColourLabel(rawValue: "Green & <Blue>"))
}
