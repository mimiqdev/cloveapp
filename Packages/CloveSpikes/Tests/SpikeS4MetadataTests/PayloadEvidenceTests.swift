import Foundation
import Testing

@testable import SpikeS4Metadata

struct PayloadEvidenceTests {
    @Test func jpegCoversProgressiveScansStuffingAndRestartMarkers() throws {
        let header: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, 0, 4, 1, 2]
        let scans: [UInt8] = [
            0xFF, 0xDA, 0, 3, 7, 9, 0xFF, 0, 8, 0xFF, 0xD0, 6,
            0xFF, 0xDA, 0, 3, 5, 4, 3, 0xFF, 0xD9,
        ]
        let original = Data(header + scans)
        let digests = try PayloadEvidence.read(original, extension: "jpg")
        #expect(digests.count == 2)
        var metadataChanged = original
        metadataChanged[6] = 33
        #expect(try PayloadEvidence.read(metadataChanged, extension: "jpg") == digests)
        var secondScanChanged = original
        secondScanChanged[secondScanChanged.count - 3] = 44
        #expect(try PayloadEvidence.read(secondScanChanged, extension: "jpg") != digests)
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(Data(original.dropLast()), extension: "jpg")
        }
    }

    @Test func heifComparesGridAndTilesWhileExcludingMetadataInsideMdat() throws {
        let original = heif(tile: 7, metadata: 11)
        let digests = try PayloadEvidence.read(original, extension: "heic")
        #expect(digests.count == 2)
        #expect(digests[0].role.contains("/grid/primary"))
        #expect(digests[1].role.contains("/hvc1"))
        #expect(try PayloadEvidence.read(heif(tile: 7, metadata: 99), extension: "heic") == digests)
        #expect(try PayloadEvidence.read(heif(tile: 8, metadata: 11), extension: "heic") != digests)
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(Data(original.dropLast()), extension: "heic")
        }
    }

    @Test(arguments: [false, true])
    func tiffComparesRawStripsAndRejectsTruncation(littleEndian: Bool) throws {
        func uint(_ value: Int, _ bytes: Int) -> Data {
            let shifts = littleEndian ? Array(0..<bytes) : Array((0..<bytes).reversed())
            return Data(shifts.map { UInt8((value >> ($0 * 8)) & 255) })
        }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> Data {
            var result = uint(tag, 2) + uint(type, 2) + uint(count, 4)
            if type == 3 {
                result += uint(value, 2) + Data([0, 0])
            } else {
                result += uint(value, 4)
            }
            return result
        }
        var file = Data((littleEndian ? "II" : "MM").utf8) + uint(42, 2) + uint(8, 4) + uint(3, 2)
        file += entry(262, 3, 1, 32803)
        file += entry(273, 4, 1, 50)
        file += entry(279, 4, 1, 4)
        file += uint(0, 4) + Data([1, 2, 3, 4])
        let original = try PayloadEvidence.read(file, extension: "dng")
        #expect(original.count == 1)
        #expect(original[0].role.contains("/raw/strip/"))
        file[53] = 5
        #expect(try PayloadEvidence.read(file, extension: "dng") != original)
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(Data(file.dropLast()), extension: "dng")
        }
        file.replaceSubrange(46..<50, with: uint(8, 4))
        #expect(throws: (any Error).self) { try PayloadEvidence.read(file, extension: "dng") }
    }

    @Test func emptyAndUnsupportedContainersFailClosed() {
        for ext in ["jpg", "heic", "dng", "unknown"] {
            #expect(throws: (any Error).self) { try PayloadEvidence.read(Data(), extension: ext) }
        }
    }

    @Test func jpegSpliceRejectsDuplicateAndExtendedPackets() {
        func segment(_ signature: String) -> Data {
            let body = Data((signature + "\0<x/>").utf8)
            return Data([0xFF, 0xE1]) + be(body.count + 2, 2) + body
        }
        let packet = segment("http://ns.adobe.com/xap/1.0/")
        let duplicate = Data([0xFF, 0xD8]) + packet + packet + Data([0xFF, 0xD9])
        let extended =
            Data([0xFF, 0xD8]) + segment("http://ns.adobe.com/xmp/extension/") + Data([0xFF, 0xD9])
        #expect(throws: (any Error).self) { try JPEGPacket.metadata(in: duplicate) }
        #expect(throws: (any Error).self) { try JPEGPacket.metadata(in: extended) }
    }

    private func be(_ value: Int, _ bytes: Int) -> Data {
        Data((0..<bytes).reversed().map { UInt8((value >> ($0 * 8)) & 255) })
    }

    private func box(_ type: String, _ contents: Data) -> Data {
        be(contents.count + 8, 4) + Data(type.utf8) + contents
    }

    private func heif(tile: UInt8, metadata: UInt8) -> Data {
        let ftyp = box("ftyp", Data("heic".utf8) + be(0, 4))
        let pitm = box("pitm", be(0, 4) + be(1, 2))
        let types = ["grid", "hvc1", "mime"]
        var infos = Data()
        for (index, type) in types.enumerated() {
            infos += box(
                "infe",
                Data([2, 0, 0, 0]) + be(index + 1, 2) + be(0, 2) + Data(type.utf8) + Data([0]))
        }
        let iinf = box("iinf", be(0, 4) + be(3, 2) + infos)
        func locations(start: Int) -> Data {
            var entries = Data([0, 0, 0, 0, 0x44, 0]) + be(3, 2)
            for index in 0..<3 {
                entries +=
                    be(index + 1, 2) + be(0, 2) + be(1, 2) + be(start + index * 2, 4) + be(2, 4)
            }
            return box("iloc", entries)
        }
        let dummy = box("meta", be(0, 4) + pitm + iinf + locations(start: 0))
        let meta = box(
            "meta", be(0, 4) + pitm + iinf + locations(start: ftyp.count + dummy.count + 8))
        return ftyp + meta + box("mdat", Data([0, 1, tile, tile, metadata, metadata]))
    }
}
