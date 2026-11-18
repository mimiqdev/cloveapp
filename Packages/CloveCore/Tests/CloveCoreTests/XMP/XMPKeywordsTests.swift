import Foundation
import Testing

import CloveCore

private actor KeywordsImageIOVerifier {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.XMPKeywordsImageIO")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    func read(_ data: Data) -> (rating: String?, label: String?, keywords: [String])? {
        XMPImageIOReader.marks(from: data)
    }
}

private let imageIOVerifier = KeywordsImageIOVerifier()

@Suite("XMP keywords")
struct XMPKeywordsTests {
    @Test func readsAndDeduplicatesKeywordsWhilePreservingCaseAndOrder() throws {
        let packet = xmpDescriptionPacket(
            namespaces: """
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                  xmlns:dc="http://purl.org/dc/elements/1.1/"
                """,
            body: """
                  <dc:subject>
                   <rdf:Bag>
                    <rdf:li>Harbour</rdf:li>
                    <rdf:li/>
                    <rdf:li>harbour</rdf:li>
                    <rdf:li>Harbour</rdf:li>
                    <rdf:li>A &amp; B</rdf:li>
                    <rdf:li><![CDATA[<Winter>]]></rdf:li>
                   </rdf:Bag>
                  </dc:subject>
                """)

        let marks = try xmpCodec.read(packet)
        #expect(marks.keywords == ["Harbour", "harbour", "A & B", "<Winter>"])
    }

    @Test func readsKeywordsByDublinCoreNamespaceURIAndIgnoresImpostorPrefix() throws {
        let aliased = xmpDescriptionPacket(
            namespaces: "xmlns:terms=\"http://purl.org/dc/elements/1.1/\"",
            body: "<terms:subject><rdf:Bag><rdf:li>fjord</rdf:li></rdf:Bag></terms:subject>")
        #expect(try xmpCodec.read(aliased).keywords == ["fjord"])

        let impostor = xmpDescriptionPacket(
            namespaces: "xmlns:dc=\"https://example.com/not-dc/\"",
            body: "<dc:subject><rdf:Bag><rdf:li>ignored</rdf:li></rdf:Bag></dc:subject>")
        #expect(try xmpCodec.read(impostor).keywords.isEmpty)
    }

    @Test func readsEmptySubjectAndEmptyBagAsNoKeywords() throws {
        let shapes = [
            "<dc:subject/>",
            "<dc:subject>  \n </dc:subject>",
            "<dc:subject><rdf:Bag/></dc:subject>",
        ]
        for body in shapes {
            let packet = xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                body: body)
            #expect(try xmpCodec.read(packet).keywords.isEmpty)
        }
    }

    @Test func readsAndWritesAcrossUnqualifiedMultipleDescriptions() throws {
        let packet = xmpPacket(
            """
              <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmp:Rating="4" xmp:Label="Blue"/>
              <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
               <dc:subject><rdf:Bag><rdf:li>sea</rdf:li></rdf:Bag></dc:subject>
              </rdf:Description>
            """)

        let before = try xmpCodec.read(packet)
        #expect(before.rating == .rated(try #require(Rating(rawValue: 4))))
        #expect(before.label == ColourLabel(colour: .blue))
        #expect(before.keywords == ["sea"])

        let updated = try xmpCodec.write(
            XMPEdit(
                rating: .set(try #require(Rating(rawValue: 5))),
                keywords: .set(["sea", "storm"])),
            into: packet)
        let after = try xmpCodec.read(updated)
        #expect(after.rating == .rated(try #require(Rating(rawValue: 5))))
        #expect(after.label == ColourLabel(colour: .blue))
        #expect(after.keywords == ["sea", "storm"])
        #expect(
            String(decoding: updated, as: UTF8.self).components(separatedBy: "<rdf:Description")
                .count == 3)
    }

    @Test func refusesMalformedOrMisplacedSubjectShapes() throws {
        let qualifiedShapes = [
            xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                attributes: "dc:subject=\"plain\""),
            xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                body: "<dc:subject>plain</dc:subject>"),
            xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                body: "<dc:subject><rdf:Seq><rdf:li>a</rdf:li></rdf:Seq></dc:subject>"),
            xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                body:
                    "<dc:subject><rdf:Bag><rdf:li xml:lang=\"en\">a</rdf:li></rdf:Bag></dc:subject>"
            ),
            xmpDescriptionPacket(
                namespaces: """
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                    """,
                body: "<dc:subject rdf:ID=\"s1\"><rdf:Bag/></dc:subject>"),
        ]
        for packet in qualifiedShapes {
            #expect(xmpError { _ = try xmpCodec.read(packet) } == .qualifiedMark(.keywords))
        }

        let misplaced = xmpDescriptionPacket(
            namespaces: """
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                  xmlns:acme="https://example.com/ns/acme/1.0/"
                """,
            body:
                "<acme:Group><dc:subject><rdf:Bag><rdf:li>a</rdf:li></rdf:Bag></dc:subject></acme:Group>"
        )
        #expect(xmpError { _ = try xmpCodec.read(misplaced) } == .misplacedMark(.keywords))

        let duplicate = xmpDescriptionPacket(
            namespaces: "xmlns:dc=\"http://purl.org/dc/elements/1.1/\"",
            body: """
                  <dc:subject><rdf:Bag><rdf:li>a</rdf:li></rdf:Bag></dc:subject>
                  <dc:subject><rdf:Bag><rdf:li>b</rdf:li></rdf:Bag></dc:subject>
                """)
        #expect(xmpError { _ = try xmpCodec.read(duplicate) } == .duplicateMark(.keywords))

        let severalDescriptions = xmpPacket(
            """
              <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
               <dc:subject><rdf:Bag><rdf:li>a</rdf:li></rdf:Bag></dc:subject>
              </rdf:Description>
              <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
               <dc:subject><rdf:Bag><rdf:li>b</rdf:li></rdf:Bag></dc:subject>
              </rdf:Description>
            """)
        #expect(
            xmpError { _ = try xmpCodec.read(severalDescriptions) } == .marksInSeveralDescriptions)
    }

    @Test func refusesKeywordTextThatXMLCannotCarry() throws {
        let packet = xmpDescriptionPacket(attributes: "xmp:Rating=\"1\"")
        #expect(
            xmpError { _ = try xmpCodec.write(.keywords(["bad\u{0000}word"]), into: packet) }
                == .unsupportedKeywordText)
        #expect(
            xmpError { _ = try xmpCodec.write(.keywords(["bad\u{0000}word"]), into: nil) }
                == .unsupportedKeywordText)
    }

    @Test func writesReplacesAndClearsKeywordsWithoutTouchingOtherBytes() async throws {
        let original = try Data(
            contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
                "fixtures/xmp/empty-description.xmp"))
        let inserted = try xmpCodec.write(
            .keywords(["Bergen", "winter & snow", "Bergen", ""]), into: original)
        #expect(try xmpCodec.read(inserted).keywords == ["Bergen", "winter & snow"])
        #expect(
            try XMPPreservation.outsideOwnedMarks(original)
                == XMPPreservation.outsideOwnedMarks(inserted))
        let interopInserted = try #require(await imageIOVerifier.read(inserted))
        #expect(interopInserted.keywords == ["Bergen", "winter & snow"])

        let cleared = try xmpCodec.write(.keywords([]), into: inserted)
        #expect(try xmpCodec.read(cleared).keywords.isEmpty)
        #expect(
            try XMPPreservation.outsideOwnedMarks(original)
                == XMPPreservation.outsideOwnedMarks(cleared))

        let clearedAgain = try xmpCodec.write(.keywords([]), into: cleared)
        #expect(clearedAgain == cleared)
    }

    @Test func rewritingIdenticalKeywordsKeepsEveryByteIdentical() throws {
        let original = try Data(
            contentsOf: XMPTestFixtures.repositoryRoot.appendingPathComponent(
                "fixtures/xmp/capture-one.xmp"))
        let output = try xmpCodec.write(.keywords(["studio", "test shot"]), into: original)
        #expect(output == original)
    }

    @Test func avoidsNamespacePrefixCollisionsWhenInsertingKeywords() async throws {
        let packet = xmpDescriptionPacket(
            namespaces: """
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                  xmlns:dc="https://example.com/custom-dc/"
                """,
            attributes: "dc:custom=\"keep\"")
        let output = try xmpCodec.write(.keywords(["dawn"]), into: packet)
        #expect(try xmpCodec.read(output).keywords == ["dawn"])
        #expect(String(decoding: output, as: UTF8.self).contains("dc:custom=\"keep\""))
        let interop = try #require(await imageIOVerifier.read(output))
        #expect(interop.keywords == ["dawn"])
    }

    @Test func createsMinimalPacketWithAndWithoutKeywords() async throws {
        let withKeywords = try xmpCodec.write(.keywords(["harbour", "dawn", "harbour"]), into: nil)
        #expect(try xmpCodec.read(withKeywords).keywords == ["harbour", "dawn"])
        let interop = try #require(await imageIOVerifier.read(withKeywords))
        #expect(interop.keywords == ["harbour", "dawn"])

        let emptyKeywords = try xmpCodec.write(.keywords([]), into: nil)
        let emptyText = String(decoding: emptyKeywords, as: UTF8.self)
        #expect(!emptyText.contains("dc:subject"))
        #expect(!emptyText.contains("xmlns:dc"))
        #expect(try xmpCodec.read(emptyKeywords).keywords.isEmpty)
    }

    @Test func hierarchicalSubjectSyncPrunesOnlyOnKeywordRemoval() throws {
        let original = xmpDescriptionPacket(
            namespaces: """
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                  xmlns:dc="http://purl.org/dc/elements/1.1/"
                  xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
                """,
            body: """
                  <dc:subject><rdf:Bag><rdf:li>Bergen</rdf:li><rdf:li>Norway</rdf:li><rdf:li>sea</rdf:li></rdf:Bag></dc:subject>
                  <lr:hierarchicalSubject><rdf:Bag><rdf:li>Places|Norway|Bergen</rdf:li><rdf:li>Nature|sea</rdf:li></rdf:Bag></lr:hierarchicalSubject>
                """)

        // Reordering or adding keywords keeps lr:hierarchicalSubject byte-for-byte intact.
        let added = try xmpCodec.write(
            .keywords(["sea", "Norway", "Bergen", "fjord"]), into: original)
        let addedText = String(decoding: added, as: UTF8.self)
        #expect(
            addedText.contains(
                "<lr:hierarchicalSubject><rdf:Bag><rdf:li>Places|Norway|Bergen</rdf:li><rdf:li>Nature|sea</rdf:li></rdf:Bag></lr:hierarchicalSubject>"
            ))

        // Removing Norway and Bergen prunes Places|Norway|Bergen while keeping Nature|sea untouched.
        let pruned = try xmpCodec.write(.keywords(["sea", "fjord"]), into: added)
        let prunedText = String(decoding: pruned, as: UTF8.self)
        #expect(!prunedText.contains("Places|Norway|Bergen"))
        #expect(prunedText.contains("<rdf:li>Nature|sea</rdf:li>"))

        // Removing the remaining matched keyword prunes Nature|sea and removes lr:hierarchicalSubject.
        let allRemoved = try xmpCodec.write(.keywords([]), into: pruned)
        let allRemovedText = String(decoding: allRemoved, as: UTF8.self)
        #expect(!allRemovedText.contains("lr:hierarchicalSubject"))
    }
}
