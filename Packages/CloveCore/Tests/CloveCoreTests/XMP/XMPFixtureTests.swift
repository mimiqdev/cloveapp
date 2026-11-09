import Foundation
import Testing

import CloveCore

private let targetLabel = ColourLabel(colour: .green)

private enum Expectation {
    case readable
    case empty
    case malformed
}

private func expectation(for name: String, data: Data) -> Expectation {
    if data.isEmpty { return .empty }
    if name.lowercased().contains("malformed") { return .malformed }
    return .readable
}

/// Sets rating 3 and Green, reads them back, and proves nothing else moved.
private func assertRoundTrip(_ data: Data, _ name: String) throws {
    let rating = try #require(Rating(rawValue: 3))
    let edited = try xmpCodec.write(
        XMPEdit(rating: .set(rating), label: .set(targetLabel)), into: data)

    #expect(
        try xmpCodec.read(edited) == XMPMarks(rating: .rated(rating), label: targetLabel), "\(name)"
    )
    let interop = try #require(
        XMPImageIOReader.marks(from: edited), "\(name) was refused by ImageIO")
    #expect(interop.rating == "3", "\(name)")
    #expect(interop.label == "Green", "\(name)")
    #expect(
        try XMPPreservation.outsideOwnedMarks(data)
            == XMPPreservation.outsideOwnedMarks(edited),
        "\(name) changed a byte outside the owned properties")
    // An edit that requests nothing must not move a byte.
    #expect(try xmpCodec.write(XMPEdit(), into: data) == data, "\(name)")
}

private let committedMarks: [(name: String, rating: XMPRating, label: ColourLabel)] = [
    ("capture-one.xmp", XMPRating(3), ColourLabel(colour: .green)),
    ("custom-namespace-nested.xmp", XMPRating(2), ColourLabel(colour: .blue)),
    ("empty-description.xmp", .unrated, .clear),
    ("label-orange.xmp", XMPRating(1), ColourLabel(colour: .orange)),
    ("label-pink.xmp", XMPRating(2), ColourLabel(colour: .pink)),
    ("lightroom-full.xmp", XMPRating(5), ColourLabel(colour: .purple)),
    ("photo-mechanic.xmp", XMPRating(4), ColourLabel(colour: .red)),
    ("rating-minus-one.xmp", .external(-1), .clear),
]

@Test func readsTheCommittedSidecars() throws {
    let packets = try XMPTestFixtures.committedPackets()
    for (name, rating, label) in committedMarks {
        let data = try #require(packets.first { $0.name == name }?.data, "\(name) is missing")
        let marks = try xmpCodec.read(data)
        #expect(marks.rating == rating, "\(name)")
        #expect(marks.label == label, "\(name)")
    }
}

@Test func roundTripsEveryCommittedSidecar() throws {
    let packets = try XMPTestFixtures.committedPackets()
    #expect(packets.count >= 10)
    for (name, data) in packets {
        switch expectation(for: name, data: data) {
        case .readable:
            try assertRoundTrip(data, name)
        case .empty:
            #expect(xmpError { _ = try xmpCodec.read(data) } == .emptyPacket, "\(name)")
            let rating = try #require(Rating(rawValue: 3))
            let edit = XMPEdit(rating: .set(rating), label: .set(targetLabel))
            #expect(
                xmpError { _ = try xmpCodec.write(edit, into: data) } == .emptyPacket, "\(name)")
        case .malformed:
            #expect(isMalformedXML(xmpError { _ = try xmpCodec.read(data) }), "\(name)")
        }
    }
}

@Test func imageIOReadsTheSameMarksAsTheCodec() throws {
    let packets = try XMPTestFixtures.committedPackets()
    for (name, rating, label) in committedMarks where name != "empty-description.xmp" {
        let data = try #require(packets.first { $0.name == name }?.data, "\(name) is missing")
        let interop = try #require(
            XMPImageIOReader.marks(from: data), "\(name) was refused by ImageIO")
        switch rating {
        case .rated(let value):
            #expect(interop.rating == String(value.rawValue), "\(name)")
        case .external(let value):
            #expect(interop.rating == String(value), "\(name)")
        }
        if label.isClear {
            // ImageIO reports an explicitly empty xmp:Label as absent, not as empty text.
            #expect(interop.label == nil || interop.label == "", "\(name)")
        } else {
            #expect(interop.label == label.rawValue, "\(name)")
        }
    }
}

@Test(.enabled(if: XMPTestFixtures.set("xmp-interop") != nil))
func roundTripsTheInteropSet() throws {
    let set = try #require(XMPTestFixtures.set("xmp-interop"))
    let sidecars = XMPTestFixtures.sidecars(in: set)
    #expect(sidecars.count >= 11)
    for url in sidecars {
        let name = XMPTestFixtures.relativeName(of: url, in: set)
        let data = try Data(contentsOf: url)
        switch expectation(for: name, data: data) {
        case .readable:
            try assertRoundTrip(data, name)
        case .empty:
            #expect(xmpError { _ = try xmpCodec.read(data) } == .emptyPacket, "\(name)")
        case .malformed:
            #expect(isMalformedXML(xmpError { _ = try xmpCodec.read(data) }), "\(name)")
        }
    }
}

@Test(.enabled(if: XMPTestFixtures.set("name-collision") != nil))
func roundTripsTheNameCollisionSet() throws {
    let set = try #require(XMPTestFixtures.set("name-collision"))
    let sidecars = XMPTestFixtures.sidecars(in: set)
    #expect(sidecars.count >= 4)
    for url in sidecars {
        let name = XMPTestFixtures.relativeName(of: url, in: set)
        let data = try Data(contentsOf: url)
        try assertRoundTrip(data, name)
    }
}
