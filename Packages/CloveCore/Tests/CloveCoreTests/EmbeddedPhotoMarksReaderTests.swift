import CoreGraphics
import Foundation
import ImageIO
import Testing

import CloveCore

private actor EmbeddedMetadataTestRunner {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.EmbeddedMarksReader")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    func writeJPEG(
        to url: URL,
        xmpPacket: Data? = nil,
        iptcKeywords: [String]? = nil
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))

        var properties: [CFString: Any] = [:]
        if let iptcKeywords {
            properties[kCGImagePropertyIPTCDictionary] = [
                kCGImagePropertyIPTCKeywords: iptcKeywords
            ]
        }

        if let xmpPacket {
            let metadata = try #require(CGImageMetadataCreateFromXMPData(xmpPacket as CFData))
            CGImageDestinationAddImageAndMetadata(
                destination, image, metadata, properties as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
    }

    func read(at url: URL) -> XMPMarks? {
        EmbeddedPhotoMarksReader.read(at: url)
    }
}

@Suite("Embedded photo marks reader")
struct EmbeddedPhotoMarksReaderTests {
    private let runner = EmbeddedMetadataTestRunner()

    @Test func readsEmbeddedXMPRatingLabelAndKeywordsFromJPEG() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let jpegURL = folder.file("IMG_0001.JPG")
        let rating = try #require(Rating(rawValue: 4))
        let packet = try XMPCodec().write(
            XMPEdit(
                rating: .set(rating),
                label: .set(ColourLabel(colour: .green)),
                keywords: .set(["harbour", "winter"])),
            into: nil)

        try await runner.writeJPEG(
            to: jpegURL, xmpPacket: packet, iptcKeywords: ["fallback-ignored"])
        let marks = try #require(await runner.read(at: jpegURL))

        #expect(marks.rating == .rated(rating))
        #expect(marks.label == ColourLabel(colour: .green))
        #expect(marks.keywords == ["harbour", "winter"])
    }

    @Test func fallsBackToIPTCKeywordsWhenDCSubjectIsAbsent() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let jpegURL = folder.file("IMG_0002.JPG")

        try await runner.writeJPEG(to: jpegURL, iptcKeywords: ["fjord", "fjord", "", "Bergen"])
        let marks = try #require(await runner.read(at: jpegURL))

        #expect(marks.rating == .unrated)
        #expect(marks.label == .clear)
        #expect(marks.keywords == ["fjord", "Bergen"])
    }

    @Test func returnsNilForMissingFileOrUnmarkedJPEG() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }

        #expect(await runner.read(at: folder.file("missing.JPG")) == nil)

        let plainURL = folder.file("plain.JPG")
        try await runner.writeJPEG(to: plainURL)
        #expect(await runner.read(at: plainURL)?.keywords.isEmpty ?? true)
    }
}
