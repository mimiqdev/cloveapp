import Foundation
import Testing

import CloveCore

private let green = ColourLabel(colour: .green)

@Test func addsMarksToAnEmptyDescription() throws {
    let original = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
            "fixtures/xmp/empty-description.xmp"))
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 3))), label: .set(green)),
        into: original)

    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 3))), label: green))
    let interop = try #require(XMPImageIOReader.marks(from: output))
    #expect(interop.rating == "3")
    #expect(interop.label == "Green")
    // Byte-for-byte proof that only the owned properties are new.
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
    // One description, not two; the new properties live inside it.
    #expect(
        String(decoding: output, as: UTF8.self).components(separatedBy: "<rdf:Description").count
            == 2)
}

@Test func addsMarksToADescriptionWithOtherProperties() throws {
    let original = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"2\"",
        body: """
              <dc:subject xmlns:dc="http://purl.org/dc/elements/1.1/">
               <rdf:Bag><rdf:li>keep me</rdf:li></rdf:Bag>
              </dc:subject>
            """)
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 5))), label: .set(.clear)),
        into: original)

    #expect(try xmpCodec.read(output).rating == .rated(try #require(Rating(rawValue: 5))))
    #expect(try xmpCodec.read(output).label == .clear)
    #expect(String(decoding: output, as: UTF8.self).contains("<rdf:li>keep me</rdf:li>"))
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func changesAttributeMarksInPlace() throws {
    let original = xmpDescriptionPacket(
        attributes: "xmp:Rating='2' xmp:Label='Blue' xmp:CreatorTool=\"Other\"")
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 4))), label: .set(green)),
        into: original)
    let text = String(decoding: output, as: UTF8.self)

    #expect(text.contains("xmp:Rating='4'"))
    #expect(text.contains("xmp:Label='Green'"))
    #expect(text.contains("xmp:CreatorTool=\"Other\""))
    // The values were replaced in place; no element form was added.
    #expect(!text.contains("<xmp:Rating"))
    #expect(!text.contains("<xmp:Label"))
    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 4))), label: green))
}

@Test func changesElementMarksInPlace() throws {
    let original = xmpDescriptionPacket(
        body: """
              <xmp:Rating>2</xmp:Rating>
              <xmp:Label>
                Blue
              </xmp:Label>
            """)
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 1))), label: .set(.clear)),
        into: original)
    let text = String(decoding: output, as: UTF8.self)

    #expect(text.contains("<xmp:Rating>1</xmp:Rating>"))
    #expect(!text.contains("<xmp:Label"))
    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 1))), label: .clear))
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func clearsLabelAttributesWithoutTouchingTheRating() throws {
    let original = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"4\" xmp:Label=\"Pink\" xmp:CreatorTool=\"Other\"")
    let output = try xmpCodec.write(XMPEdit(label: .set(.clear)), into: original)
    let text = String(decoding: output, as: UTF8.self)

    #expect(!text.contains("xmp:Label"))
    #expect(text.contains("xmp:Rating=\"4\""))
    #expect(text.contains("xmp:CreatorTool=\"Other\""))
    #expect(
        try xmpCodec.read(output) == XMPMarks(rating: .rated(try #require(Rating(rawValue: 4)))))
}

@Test func clearingAnAbsentLabelKeepsEveryByte() throws {
    let original = xmpDescriptionPacket(attributes: "xmp:Rating=\"1\"")
    let output = try xmpCodec.write(XMPEdit(label: .set(.clear)), into: original)
    #expect(output == original)
}

@Test func writesRatingZeroAsAnExplicitValue() throws {
    // Documented choice: rating zero is `xmp:Rating="0"`, which other apps read as unrated,
    // so clearing a rating stays an explicit value rather than a missing field.
    let original = xmpDescriptionPacket(attributes: "xmp:Rating=\"4\"")
    let output = try xmpCodec.write(XMPEdit(rating: .set(.unrated)), into: original)
    #expect(String(decoding: output, as: UTF8.self).contains("xmp:Rating=\"0\""))
    #expect(try xmpCodec.read(output).rating == .rated(.unrated))
}

@Test(arguments: [6, -2])
func keepsAnotherOutOfRangeRatingWhenOnlyTheLabelChanges(value: Int) throws {
    let original = xmpDescriptionPacket(attributes: "xmp:Rating=\"\(value)\"")
    let output = try xmpCodec.write(XMPEdit(label: .set(green)), into: original)
    let text = String(decoding: output, as: UTF8.self)

    // Any value outside −1…5 keeps its bytes and reads as unrated (PRD P0-07).
    #expect(text.contains("xmp:Rating=\"\(value)\""))

    let before = try xmpCodec.read(original)
    #expect(before.rating == .external(value))
    let after = try xmpCodec.read(output)
    #expect(after.rating == .external(value))
    #expect(after.label == green)
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func keepsRejectWhenOnlyTheLabelChanges() throws {
    let original = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
            "fixtures/xmp/rating-minus-one.xmp"))
    let output = try xmpCodec.write(XMPEdit(label: .set(green)), into: original)
    let text = String(decoding: output, as: UTF8.self)

    // −1 is Reject, and a label-only write keeps its exact bytes (PRD P0-07).
    #expect(text.contains("xmp:Rating=\"-1\""))
    let before = try xmpCodec.read(original)
    #expect(before.rating == .rated(.rejected))
    let after = try xmpCodec.read(output)
    #expect(after.rating == .rated(.rejected))
    #expect(after.label == green)
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func writesRatingMinusOneForReject() throws {
    let original = xmpDescriptionPacket(attributes: "xmp:Rating=\"4\"")
    let output = try xmpCodec.write(XMPEdit(rating: .set(.rejected)), into: original)
    #expect(String(decoding: output, as: UTF8.self).contains("xmp:Rating=\"-1\""))
    #expect(try xmpCodec.read(output).rating == .rated(.rejected))
}

@Test func replacingRejectWithStarsWritesThem() throws {
    let original = xmpDescriptionPacket(attributes: "xmp:Rating=\"-1\"")
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 2)))), into: original)
    #expect(try xmpCodec.read(output).rating == .rated(try #require(Rating(rawValue: 2))))
    #expect(!String(decoding: output, as: UTF8.self).contains("-1"))
}

@Test(arguments: [LabelColour.orange, LabelColour.pink])
func writesTheExtendedColours(colour: LabelColour) throws {
    let label = ColourLabel(colour: colour)
    let original = xmpDescriptionPacket(attributes: "xmp:Label=\"Red\"")
    let output = try xmpCodec.write(XMPEdit(label: .set(label)), into: original)
    #expect(try xmpCodec.read(output).label == label)
    #expect(String(decoding: output, as: UTF8.self).contains("xmp:Label=\"\(colour.rawValue)\""))
}

@Test(arguments: [
    "\u{6A59}\u{8272}", "cafe\u{301}", "A & B <c> \"d\" 'e'", "line one\nline two", "tab\there",
])
func writesUnknownLabelsWithoutChangingTheirText(text: String) throws {
    for form in ["attribute", "element", "absent"] {
        let original: Data
        switch form {
        case "attribute": original = xmpDescriptionPacket(attributes: "xmp:Label=\"old\"")
        case "element": original = xmpDescriptionPacket(body: "<xmp:Label>old</xmp:Label>")
        default: original = xmpDescriptionPacket()
        }
        let output = try xmpCodec.write(
            XMPEdit(label: .set(ColourLabel(rawValue: text))), into: original)
        let label = try xmpCodec.read(output).label
        #expect(Array(label.rawValue.utf8) == Array(text.utf8), "\(form) form changed the text")
    }
}

@Test func reusesAnExistingXMPPrefixWhenInserting() throws {
    let original = xmpDescriptionPacket(
        namespaces: "xmlns:photo=\"http://ns.adobe.com/xap/1.0/\"",
        body: "<photo:CreatorTool>Other</photo:CreatorTool>")
    let output = try xmpCodec.write(XMPEdit(label: .set(.init(colour: .orange))), into: original)
    #expect(String(decoding: output, as: UTF8.self).contains("<photo:Label>Orange</photo:Label>"))
    #expect(try xmpCodec.read(output).label == ColourLabel(colour: .orange))
}

@Test func writesOnlyIntoTheDescriptionThatHoldsTheMarks() throws {
    let marker = """
        <rdf:Description rdf:about="#history-step" \
        xmlns:stEvt="http://ns.adobe.com/xap/1.0/sType/ResourceEvent#" \
        stEvt:action="saved"/>
        """
    let original = xmpPacket(
        """
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="4"/>
          \(marker)
        """)
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 2))), label: .set(green)),
        into: original)
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains(marker))
    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 2))), label: green))
}

@Test(arguments: [
    "capture-one.xmp", "lightroom-full.xmp", "photo-mechanic.xmp", "custom-namespace-nested.xmp",
    "label-orange.xmp", "label-pink.xmp", "empty-description.xmp", "rating-minus-one.xmp",
])
func roundTripKeepsEveryUnrelatedByte(fixture: String) throws {
    let original = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent("fixtures/xmp/\(fixture)")
    )
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 3))), label: .set(green)),
        into: original)

    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 3))), label: green))
    let interop = try #require(
        XMPImageIOReader.marks(from: output), "\(fixture) was refused by ImageIO")
    #expect(interop.rating == "3")
    #expect(interop.label == "Green")
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )

    // No requested change means no byte may move.
    #expect(try xmpCodec.write(XMPEdit(), into: original) == original)
}

@Test func rewritingTheCurrentMarksKeepsTheBytesIdentical() throws {
    // capture-one.xmp already holds 3 and Green in attribute form.
    let original = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
            "fixtures/xmp/capture-one.xmp"))
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 3))), label: .set(green)),
        into: original)
    #expect(output == original)
}

@Test func createsAMinimalWrappedPacketFromNothing() throws {
    let rating = try #require(Rating(rawValue: 3))
    let output = try xmpCodec.write(XMPEdit(rating: .set(rating), label: .set(green)), into: nil)
    let text = String(decoding: output, as: UTF8.self)

    #expect(text.hasPrefix("<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>"))
    #expect(text.hasSuffix("<?xpacket end=\"w\"?>\n"))
    #expect(text.contains("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">"))
    #expect(
        text.contains("<rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\">")
    )
    #expect(text.contains("<xmp:Rating>3</xmp:Rating>"))
    #expect(text.contains("<xmp:Label>Green</xmp:Label>"))
    #expect(try xmpCodec.read(output) == XMPMarks(rating: .rated(rating), label: green))
    let interop = try #require(
        XMPImageIOReader.marks(from: output), "ImageIO refused the new packet")
    #expect(interop.rating == "3")
    #expect(interop.label == "Green")
}

@Test func createsAPacketWithOnlyTheRequestedMark() throws {
    let labelOnly = try xmpCodec.write(XMPEdit(label: .set(.init(colour: .pink))), into: nil)
    #expect(!String(decoding: labelOnly, as: UTF8.self).contains("<xmp:Rating"))
    #expect(try xmpCodec.read(labelOnly).label == ColourLabel(colour: .pink))

    let ratingOnly = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 1)))), into: nil)
    #expect(!String(decoding: ratingOnly, as: UTF8.self).contains("<xmp:Label"))
    #expect(try xmpCodec.read(ratingOnly).rating == .rated(try #require(Rating(rawValue: 1))))

    let empty = try xmpCodec.write(XMPEdit(), into: nil)
    #expect(try xmpCodec.read(empty) == .unmarked)
    #expect(
        String(decoding: empty, as: UTF8.self).contains(
            "<rdf:Description rdf:about=\"\" xmlns:xmp="))
}

@Test func createsAPacketWithAnEscapedUnknownLabel() throws {
    let text = "A & B <c> \"d\""
    let output = try xmpCodec.write(XMPEdit(label: .set(ColourLabel(rawValue: text))), into: nil)
    #expect(try xmpCodec.read(output).label == ColourLabel(rawValue: text))
    let interop = try #require(XMPImageIOReader.marks(from: output))
    #expect(interop.label == text)
}

@Test(arguments: [
    "capture-one.xmp", "lightroom-full.xmp", "photo-mechanic.xmp", "custom-namespace-nested.xmp",
    "empty-description.xmp", "rating-minus-one.xmp",
])
func neverWritesACloveNamespaceOrAnUnrequestedField(fixture: String) throws {
    let original = try Data(
        contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent("fixtures/xmp/\(fixture)")
    )
    let edits: [XMPEdit] = [
        XMPEdit(rating: .set(try #require(Rating(rawValue: 3)))),
        XMPEdit(label: .set(green)),
        XMPEdit(label: .set(.clear)),
        XMPEdit(rating: .set(.unrated)),
    ]
    let input = String(decoding: original, as: UTF8.self)
    for edit in edits {
        let output = try xmpCodec.write(edit, into: original)
        let text = String(decoding: output, as: UTF8.self)
        // Preserving another app's bytes is the point, so a write may never add either.
        #expect(occurrences(of: "clove", in: text) == occurrences(of: "clove", in: input))
        #expect(occurrences(of: "Reject", in: text) == occurrences(of: "Reject", in: input))
        #expect(occurrences(of: "xmlns:clove", in: text) == 0)
        if case .set = edit.rating {
            #expect(!text.contains("Rating=\"-1\""))
            #expect(!text.contains("Rating='-1'"))
            #expect(!text.contains(">-1<"))
        } else {
            #expect(
                occurrences(of: "Rating=\"-1\"", in: text)
                    == occurrences(of: "Rating=\"-1\"", in: input))
        }
    }
}

@Test func writesIntoASelfClosingElementMark() throws {
    // A self-closing label element is an empty label; setting one rewrites that element.
    let selfClosing = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"2\"", body: "<xmp:Label/>")
    #expect(try xmpCodec.read(selfClosing).label == .clear)
    let label = ColourLabel(colour: .purple)
    let output = try xmpCodec.write(XMPEdit(label: .set(label)), into: selfClosing)
    #expect(String(decoding: output, as: UTF8.self).contains("<xmp:Label>Purple</xmp:Label>"))
    #expect(!String(decoding: output, as: UTF8.self).contains("<xmp:Label/>"))
    #expect(try xmpCodec.read(output).label == label)
}

@Test func writesIntoASelfClosingDescriptionWithAnAttributeMark() throws {
    // Replacing the last attribute value and expanding `/>` touch disjoint ranges.
    let original = xmpPacket(
        """
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="2"/>
        """)
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 4))), label: .set(green)), into: original
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("xmp:Rating=\"4\""))
    #expect(text.contains("<xmp:Label>Green</xmp:Label>"))
    #expect(text.contains("</rdf:Description>"))
    #expect(
        try xmpCodec.read(output)
            == XMPMarks(rating: .rated(try #require(Rating(rawValue: 4))), label: green))
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func createdPacketsNeverCarryACloveNamespaceOrAnUnrequestedField() throws {
    let edits: [XMPEdit] = [
        XMPEdit(rating: .set(try #require(Rating(rawValue: 3))), label: .set(green)),
        XMPEdit(rating: .set(.unrated)),
        XMPEdit(label: .set(.clear)),
        XMPEdit(),
    ]
    for edit in edits {
        let text = String(decoding: try xmpCodec.write(edit, into: nil), as: UTF8.self)
        #expect(!text.lowercased().contains("clove"))
        #expect(!text.contains("Reject"))
        #expect(!text.contains("-1"))
    }
}

@Test func expandsASelfClosingMarkWithItsOwnNamespaceDeclaration() throws {
    // The mark declares its prefix on itself; expanding `/>` must keep that declaration.
    let original = xmpDescriptionPacket(
        body: """
              <photo:Label xmlns:photo="http://ns.adobe.com/xap/1.0/"/>
            """)
    let output = try xmpCodec.write(XMPEdit(label: .set(.init(colour: .orange))), into: original)
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("xmlns:photo=\"http://ns.adobe.com/xap/1.0/\""))
    #expect(try xmpCodec.read(output).label == ColourLabel(colour: .orange))
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}

@Test func writesIntoADescriptionWithoutAnAboutAttribute() throws {
    // A blank-node description is still the only place the marks can belong.
    let original = xmpPacket(
        """
          <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="1"/>
        """)
    let output = try xmpCodec.write(XMPEdit(label: .set(green)), into: original)
    #expect(try xmpCodec.read(output) == XMPMarks(rating: XMPRating(1), label: green))
}

@Test func changesMixedAttributeAndElementMarks() throws {
    // Some apps write one mark as an attribute and the other as an element.
    let original = xmpDescriptionPacket(
        attributes: "xmp:Rating=\"2\"", body: "<xmp:Label>Blue</xmp:Label>")
    let output = try xmpCodec.write(
        XMPEdit(rating: .set(try #require(Rating(rawValue: 5))), label: .set(green)), into: original
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("xmp:Rating=\"5\""))
    #expect(text.contains("<xmp:Label>Green</xmp:Label>"))
    #expect(try xmpCodec.read(output) == XMPMarks(rating: XMPRating(5), label: green))
    #expect(
        try XMPPreservation.outsideOwnedMarks(original) == XMPPreservation.outsideOwnedMarks(output)
    )
}
