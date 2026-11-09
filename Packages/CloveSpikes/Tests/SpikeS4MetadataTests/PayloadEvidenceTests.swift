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
        #expect(digests.filter { $0.sourceItemID != nil }.count == 7)
        #expect(digests.contains { $0.role == "HEIF/primary/grid" })
        #expect(digests.contains { $0.role.contains("/dimg/out/0/hvc1") })
        #expect(digests.contains { $0.role.contains("/auxl/in/0/hvc1") })
        #expect(digests.contains { $0.role.contains("/thmb/in/0/hvc1") })
        #expect(digests.contains { $0.role.contains("/dimg/in/0/tmap") })
        #expect(try PayloadEvidence.read(heif(tile: 7, metadata: 99), extension: "heic") == digests)
        #expect(try PayloadEvidence.read(heif(tile: 8, metadata: 11), extension: "heic") != digests)
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(Data(original.dropLast()), extension: "heic")
        }
    }

    @Test func heifRenumberingKeepsContentButOrderOwnershipAndByteChangesFail() throws {
        let original = try PayloadEvidence.read(heif(tile: 7, metadata: 11), extension: "HIF")
        let renumbered = try PayloadEvidence.read(
            heif(tile: 7, metadata: 99, renumbered: true), extension: "hif")
        #expect(original != renumbered)  // source IDs are retained as diagnostics
        #expect(PayloadEvidence.contentMatches(original, renumbered))
        func snapshot(_ payloads: [PayloadDigest]) -> MetadataSnapshot {
            MetadataSnapshot(
                fileBytes: 1, fileSHA256: "unused", payloads: payloads, makerNotes: [],
                jpegEXIFPreviews: [], imageCount: 1, metadata: [:], properties: [:])
        }
        var result = EmbeddedWriteResult(
            file: "camera.HIF", control: "camera-original", method: .copyImageSource)
        result.before = snapshot(original)
        result.after = snapshot(renumbered)
        #expect(result.payloadUnchanged && result.payloadRenumberedOnly)
        result.after?.payloads[0].sha256 = "changed"
        #expect(!result.payloadUnchanged && !result.payloadRenumberedOnly)
        for changed in [
            heif(tile: 8, metadata: 11, renumbered: true),
            heif(tile: 7, metadata: 11, swapTiles: true),
            heif(tile: 7, metadata: 11, auxiliaryOwner: 2),
            heif(tile: 7, metadata: 11, auxiliaryByte: 99),
            heif(tile: 7, metadata: 11, gainMapByte: 99),
            heif(tile: 7, metadata: 11, thumbnailByte: 99),
        ] {
            #expect(
                !PayloadEvidence.contentMatches(
                    original, try PayloadEvidence.read(changed, extension: "hif")))
        }
        #expect(
            try PayloadEvidence.makerNotes(heif(tile: 7, metadata: 11), extension: "HiF").isEmpty)
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(
                heif(tile: 7, metadata: 11, auxiliaryOwner: 99), extension: "hif")
        }
        #expect(throws: (any Error).self) {
            try PayloadEvidence.read(
                heif(tile: 7, metadata: 11, disconnected: true), extension: "hif")
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

    private func heif(
        tile: UInt8, metadata: UInt8, renumbered: Bool = false, swapTiles: Bool = false,
        auxiliaryOwner: Int = 1, auxiliaryByte: UInt8 = 21, gainMapByte: UInt8 = 31,
        thumbnailByte: UInt8 = 41, disconnected: Bool = false
    ) -> Data {
        // Primary grid, two ordered tiles, auxiliary, thumbnail, tone map, gain map, XMP.
        let types = ["grid", "hvc1", "hvc1", "hvc1", "hvc1", "tmap", "hvc1", "mime"]
        let bytes: [[UInt8]] = [
            [0, 1], [tile, tile], [8, 9], [auxiliaryByte, 22],
            [thumbnailByte, 42], [0, 2], [gainMapByte, 32], [metadata, metadata],
        ]
        func id(_ index: Int) -> Int { renumbered ? index * 7 + 13 : index }
        let order = renumbered ? Array(types.indices.reversed()) : Array(types.indices)
        let ftyp = box("ftyp", Data("heic".utf8) + be(0, 4))
        let pitm = box("pitm", be(0, 4) + be(id(1), 2))
        var infos = Data()
        for index in order {
            infos += box(
                "infe",
                Data([2, 0, 0, 0]) + be(id(index + 1), 2) + be(0, 2)
                    + Data(types[index].utf8) + Data([0]))
        }
        let iinf = box("iinf", be(0, 4) + be(types.count, 2) + infos)
        func ref(_ type: String, _ from: Int, _ targets: [Int]) -> Data {
            box(
                type,
                be(id(from), 2) + be(targets.count, 2)
                    + targets.reduce(Data()) { $0 + be(id($1), 2) })
        }
        let references =
            ref("dimg", 1, swapTiles ? [3, 2] : [2, 3])
            + ref("auxl", 4, [auxiliaryOwner])
            + (disconnected ? Data() : ref("thmb", 5, [1]))
            + ref("dimg", 6, [1, 7])
        let iref = box("iref", be(0, 4) + references)
        func locations(start: Int) -> Data {
            var entries = Data([0, 0, 0, 0, 0x44, 0]) + be(types.count, 2)
            for (position, index) in order.enumerated() {
                entries +=
                    be(id(index + 1), 2) + be(0, 2) + be(1, 2)
                    + be(start + position * 2, 4) + be(2, 4)
            }
            return box("iloc", entries)
        }
        let dummy = box("meta", be(0, 4) + pitm + iinf + iref + locations(start: 0))
        let meta = box(
            "meta",
            be(0, 4) + pitm + iinf + iref
                + locations(start: ftyp.count + dummy.count + 8))
        return ftyp + meta + box("mdat", Data(order.flatMap { bytes[$0] }))
    }
}
