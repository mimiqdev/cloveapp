import Foundation
import Testing

import CloveCore

@Test(arguments: -1...5)
func classifiesInRangeRatings(value: Int) throws {
    let rating = XMPRating(value)
    #expect(rating == .rated(try #require(Rating(rawValue: value))))
    #expect(rating.rating == (try #require(Rating(rawValue: value))))
    #expect(rating.externalValue == nil)
}

@Test(arguments: [Int.min, -2, 6, 7, Int.max])
func keepsOutOfRangeRatingsExternal(value: Int) {
    let rating = XMPRating(value)
    #expect(rating == .external(value))
    #expect(rating.rating == nil)
    #expect(rating.externalValue == value)
}

@Test func ratingMinusOneIsReject() {
    #expect(XMPRating(-1) == .rated(.rejected))
    #expect(XMPRating(-1).rating == .rejected)
    #expect(XMPRating(-1).externalValue == nil)
}

@Test func unmarkedIsTheReadingOfAnEmptyPacket() {
    #expect(XMPRating.unrated == .rated(.unrated))
    #expect(XMPMarks.unmarked == XMPMarks(rating: .unrated, label: .clear))
    #expect(XMPMarks.unmarked.label.isClear)
}

@Test func editKeepsEverythingItWasNotAskedToChange() throws {
    let rating = try #require(Rating(rawValue: 4))
    let label = ColourLabel(colour: .orange)
    #expect(XMPEdit() == XMPEdit(rating: .keep, label: .keep))
    #expect(XMPEdit.rating(rating) == XMPEdit(rating: .set(rating), label: .keep))
    #expect(XMPEdit.label(label) == XMPEdit(rating: .keep, label: .set(label)))
    #expect(XMPEdit.label(.clear).label == .set(.clear))
}

@Test func ownedPropertiesUseTheStandardNamespaceAndNames() {
    #expect(XMPProperty.namespaceURI == "http://ns.adobe.com/xap/1.0/")
    #expect(XMPProperty.rating.localName == "Rating")
    #expect(XMPProperty.label.localName == "Label")
    #expect(XMPProperty.allCases == [.rating, .label])
}

@Test func publicValuesAreSendable() {
    func accept<T: Sendable>(_: T) {}
    accept(XMPCodec())
    accept(XMPMarks())
    accept(XMPEdit())
    accept(XMPRating.unrated)
    accept(XMPCodecError.emptyPacket)
    accept(LabelColour.green)
}

@Test func refusalsExplainThemselves() {
    let errors: [XMPCodecError] = [
        .emptyPacket,
        .packetTooLarge(limit: 4, byteCount: 5),
        .unsupportedEncoding,
        .documentTypeDeclaration,
        .entityDeclaration,
        .malformedXML("truncated"),
        .missingDescription,
        .ambiguousDescriptions,
        .qualifiedDescription,
        .marksInSeveralDescriptions,
        .duplicateMark(.rating),
        .misplacedMark(.label),
        .qualifiedMark(.rating),
        .invalidRating("five"),
        .unsupportedLabelText,
        .writeVerificationFailed,
    ]
    for error in errors {
        #expect(!error.description.isEmpty)
    }
}
